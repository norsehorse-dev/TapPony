import Foundation
import TapPonyKit

extension ScanOutcome: @unchecked Sendable {}

/// Why a read sent nothing.
enum ScanFailure: String, Error {
    case noProfile, noRule, noNdef, unknownLaunch
}

/// Where one reading goes, and the registry name it was sent under.
struct Routed {
    var targets: [Profile]
    var tagLabel: String
}

/// The Scan tab's brain, shaped like Android's ScanViewModel: reads a tag,
/// routes it (rules, or the active profile), sends to every target, records,
/// and gives feedback. Also drives batch mode.
@MainActor
final class ScanController: ObservableObject {

    enum State: Equatable {
        case idle
        case sending
        case done([ScanOutcome])
        case failed(TagReadError)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var reading = false

    // Batch mode
    @Published private(set) var batchOn = false
    @Published private(set) var batchResults: [ScanOutcome] = []
    @Published private(set) var batchDone = 0
    @Published private(set) var batchInFlight = 0
    @Published private(set) var skippedRepeats = 0
    var batchCount: Int { batchDone + batchInFlight }

    private unowned let model: AppModel
    private let batchReader = BatchTagReader()
    /// Changes with every new batch, so a send from an earlier batch never lands in this one.
    private var gen = 0
    private var seenInBatch = Set<String>()

    private static let maxBatchRows = 200

    init(model: AppModel) {
        self.model = model
        batchReader.onTag = { [weak self] r in self?.onBatchTag(r) }
        batchReader.onEnd = { [weak self] e in self?.batchEnded(e) }
    }

    // MARK: Routing

    /// Which technologies and extended reads the next read needs: the active
    /// profile's, or every profile's when rules or a tag's own profile can pick any of them.
    private func readSpec() -> (technologies: [String], extended: Bool)? {
        let rules = model.rules.current
        let all = model.profiles.profiles
        if rules.enabled || model.tags.current.tags.contains(where: { $0.profile != nil }) {
            guard !all.isEmpty else { return nil }
            var tech: [String] = []
            for p in all { for t in p.tag.technologies where !tech.contains(t) { tech.append(t) } }
            return (tech, all.contains { $0.tag.extendedReads })
        }
        guard let p = model.activeProfile else { return nil }
        return (p.tag.technologies, p.tag.extendedReads)
    }

    /// The profiles this reading goes to: the registry names the tag (section
    /// 16), then rules, the tag's own profile, or the active profile decide
    /// (section 14). `forced` skips the rules (Scan and Send with a chosen profile).
    func targets(for reading: TagReading, scanTimeMs: Int64, forced: Profile? = nil) -> Result<Routed, ScanFailure> {
        let all = model.profiles.profiles
        let targets: [Profile]
        let rules = model.rules.current
        var vars = Variables.build(reading, SendContext(scanTimeMs: scanTimeMs, sendTimeMs: scanTimeMs, timeZone: "UTC",
                                                        profileName: "", profileId: "", deviceLabel: "", platform: "ios",
                                                        nonce: "", seq: 0))
        let entry = Tags.find(model.tags.current, variables: vars)
        let tagLabel = entry?.label ?? ""
        vars["tag_label"] = tagLabel
        if let forced {
            targets = [forced]
        } else {
            // A rule whose profiles were all deleted has none left, so it is skipped like any rule with no profiles.
            let live = Set(all.map(\.id))
            var liveRules = rules
            liveRules.rules = rules.rules.map { r in
                var r = r
                r.profiles = r.profiles.filter { live.contains($0) }
                return r
            }
            let tagProfile = entry?.profile.flatMap { live.contains($0) ? $0 : nil }
            let route = Rules.route(liveRules, variables: vars, activeProfileId: model.activeProfile?.id, tagProfileId: tagProfile)
            targets = route.profileIds.compactMap { id in all.first { $0.id == id } }
            if targets.isEmpty {
                let ignored = rules.enabled && route.ruleId == nil && rules.unmatched == RuleSet.unmatchedIgnore
                return .failure(ignored ? .noRule : .noProfile)
            }
        }
        let sendable = targets.filter { !($0.tag.requireNdef && reading.ndef.isEmpty) }
        return sendable.isEmpty ? .failure(.noNdef) : .success(Routed(targets: sendable, tagLabel: tagLabel))
    }

    /// Sends to every target at once, records each, then plays the feedback.
    func send(_ routed: Routed, reading: TagReading, scanTimeMs: Int64) async -> [ScanOutcome] {
        let targets = routed.targets
        let tagLabel = routed.tagLabel
        let engine = model.engine
        let history = model.history
        let queue = model.queue
        let results = await withTaskGroup(of: (Int, ScanOutcome).self, returning: [(Profile, ScanOutcome)].self) { group in
            for (i, p) in targets.enumerated() {
                group.addTask { @MainActor in
                    let o = await engine.run(p, reading: reading, scanTimeMs: scanTimeMs, history: history, queue: queue, tagLabel: tagLabel)
                    return (i, o)
                }
            }
            var out: [(Int, ScanOutcome)] = []
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }.map { (targets[$0.0], $0.1) }
        }
        model.feedback.after(results)
        return results.map { $0.1 }
    }

    // MARK: Single scan

    func scan() {
        guard !reading, !batchOn, let spec = readSpec() else { return }
        reading = true
        state = .idle
        // The last batch's rows give way to this scan's result card.
        resetBatch()
        Task {
            defer { reading = false }
            do {
                let r = try await TagReaders.default().read(technologies: spec.technologies, extendedReads: spec.extended,
                                                            alert: String(localized: "Hold near the tag"))
                let scanTime = ScanEngine.nowMs()
                switch targets(for: r, scanTimeMs: scanTime) {
                case .failure(let f):
                    state = .failed(.other(f.rawValue))
                case .success(let t):
                    state = .sending
                    state = .done(await send(t, reading: r, scanTimeMs: scanTime))
                }
            } catch let e as TagReadError {
                state = .failed(e)
            } catch {
                state = .failed(.other(error.localizedDescription))
            }
        }
    }

    var canScan: Bool { TagReaders.isAvailable && readSpec() != nil }

    /// For Scan and Send: ends a batch and holds the reader so the Scan tab
    /// can't start a second Core NFC session meanwhile. False if a read is already running.
    func claimReader() -> Bool {
        if batchOn { setBatch(false) }
        guard !reading else { return false }
        reading = true
        return true
    }

    func releaseReader() {
        reading = false
    }

    // MARK: Batch

    func setBatch(_ on: Bool) {
        if on {
            guard !reading, let spec = readSpec() else { return }
            resetBatch()
            batchOn = true
            state = .idle
            batchReader.start(technologies: spec.technologies, extendedReads: spec.extended, alert: batchAlert())
        } else {
            batchReader.stop()
            batchOn = false
        }
    }

    /// Clears the count and the list; the session keeps going.
    func newBatch() {
        resetBatch()
        batchReader.setAlert(batchAlert())
    }

    private func resetBatch() {
        gen += 1
        seenInBatch.removeAll()
        batchResults = []
        batchDone = 0
        batchInFlight = 0
        skippedRepeats = 0
    }

    private func batchAlert(last: String? = nil) -> String {
        let count = String(localized: "\(batchCount) scanned")
        return [String(localized: "Tap tags one after another"), count, last].compactMap { $0 }.joined(separator: "\n")
    }

    private func onBatchTag(_ r: TagReading) {
        let key = Encoding.hexLower(r.identifier)
        let myGen = gen
        let marked = model.settings.oncePerBatch
        if marked {
            guard seenInBatch.insert(key).inserted else {
                skippedRepeats += 1
                return
            }
        }
        let scanTime = ScanEngine.nowMs()
        let t: Routed
        switch targets(for: r, scanTimeMs: scanTime) {
        case .failure(let f):
            // A read that sends nothing must not count as already sent in this batch.
            if marked { seenInBatch.remove(key) }
            batchReader.setAlert(batchAlert(last: Self.failureText(f)))
            return
        case .success(let s):
            t = s
        }
        batchInFlight += 1
        batchReader.setAlert(batchAlert())
        Task {
            let outcomes = await send(t, reading: r, scanTimeMs: scanTime)
            guard myGen == gen else { return }
            batchResults = Array((outcomes + batchResults).prefix(Self.maxBatchRows))
            batchInFlight = max(0, batchInFlight - 1)
            batchDone += 1
            let last = outcomes.first.map { o in
                let uid = o.uid.isEmpty ? "?" : o.uid
                return "\(uid): \(Self.shortResult(o))"
            }
            batchReader.setAlert(batchAlert(last: last))
        }
    }

    private func batchEnded(_ e: TagReadError) {
        batchOn = false
        if e != .cancelled { state = .failed(e) }
    }

    nonisolated static func shortResult(_ o: ScanOutcome) -> String {
        if let t = o.resultText ?? o.message { return t }
        if o.queued { return String(localized: "Queued") }
        if o.buildError != nil { return String(localized: "Not sent") }
        if let s = o.result?.status { return "HTTP \(s)" }
        return String(localized: "Network error")
    }

    nonisolated static func failureText(_ f: ScanFailure) -> String {
        switch f {
        case .unknownLaunch: return String(localized: "That launch link belongs to a tag this phone doesn't know, so nothing was sent.")
        case .noNdef: return String(localized: "This profile needs a tag with NDEF content, and this tag has none.")
        case .noRule: return String(localized: "No rule matched this tag, so nothing was sent.")
        case .noProfile: return String(localized: "Create a profile first. A profile says where each scan gets sent.")
        }
    }

    // MARK: Launch links

    /// A TapPony launch link opened the app without an in-app read (background
    /// tag reading, or the link opened elsewhere). Only tokens in the registry
    /// send anything (PROFILE_SCHEMA.md section 16).
    func launch(link: String, records: [NdefRecord]) {
        let token = Variables.launchToken(link)
        guard !token.isEmpty, model.tags.current.tags.contains(where: { $0.token == token }) else {
            state = .failed(.other(ScanFailure.unknownLaunch.rawValue))
            return
        }
        if batchOn { setBatch(false) }
        guard !reading else { return }
        resetBatch()
        let r = Tags.launchReading(link: link, records: records)
        let scanTime = ScanEngine.nowMs()
        switch targets(for: r, scanTimeMs: scanTime) {
        case .failure(let f):
            state = .failed(.other(f.rawValue))
        case .success(let routed):
            reading = true
            state = .sending
            Task {
                defer { reading = false }
                state = .done(await send(routed, reading: r, scanTimeMs: scanTime))
            }
        }
    }

    // MARK: Queue

    func sendQueuedNow() {
        Task { await model.queue.flush() }
    }
}
