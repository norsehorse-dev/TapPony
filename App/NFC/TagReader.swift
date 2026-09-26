import CoreNFC
import Foundation
import TapPonyKit
import UIKit

/// Why a read ended without a tag. The Scan tab has its own copy for each.
enum TagReadError: Error, Equatable {
    case unavailable
    case cancelled
    case timeout
    case systemBusy
    case moved
    case unsupported
    case other(String)
}

/// Reads one tag. The Core NFC implementation runs on devices; the fake
/// replays a canned reading so the UI and pipeline work in the simulator.
protocol TagReader {
    func read(technologies: [String], extendedReads: Bool, alert: String) async throws -> TagReading
}

enum TagReaders {
    static func `default`() -> TagReader {
        #if targetEnvironment(simulator)
        return FakeTagReader()
        #else
        return CoreNFCTagReader()
        #endif
    }

    static var isAvailable: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return NFCTagReaderSession.readingAvailable
        #endif
    }
}

struct FakeTagReader: TagReader {
    func read(technologies: [String], extendedReads: Bool, alert: String) async throws -> TagReading {
        try await Task.sleep(nanoseconds: 400_000_000)
        var r = TagReading(family: .mifare, tagType: "mifare_ultralight", identifier: [0x04, 0xA2, 0x7F, 0x1B, 0x5E, 0x80, 0x00])
        r.chip = "NTAG215"
        r.ndef = [NdefRecord(tnf: 1, type: [0x54], id: [], payload: [0x02] + Array("en".utf8) + Array("Simulator tag".utf8))]
        return r
    }
}

/// Core NFC reader. The session only reads; the request goes out after the
/// session closes, so a slow server can never make a good read look failed.
final class CoreNFCTagReader: NSObject, TagReader, NFCTagReaderSessionDelegate {

    private let lock = NSLock()
    private var continuation: CheckedContinuation<TagReading, Error>?
    private var session: NFCTagReaderSession?
    private var extendedReads = true

    func read(technologies: [String], extendedReads: Bool, alert: String) async throws -> TagReading {
        guard NFCTagReaderSession.readingAvailable else { throw TagReadError.unavailable }
        var polling: NFCTagReaderSession.PollingOption = []
        if technologies.contains("iso14443") || technologies.contains("iso7816") { polling.insert(.iso14443) }
        if technologies.contains("iso15693") { polling.insert(.iso15693) }
        if technologies.contains("felica") { polling.insert(.iso18092) }
        if polling.isEmpty { polling = [.iso14443] }
        let pollingOption = polling
        self.extendedReads = extendedReads

        return try await withCheckedThrowingContinuation { cont in
            lock.lock()
            continuation = cont
            lock.unlock()
            DispatchQueue.main.async {
                let created: NFCTagReaderSession? = NFCTagReaderSession(pollingOption: pollingOption, delegate: self, queue: nil)
                guard let s = created else {
                    self.finish(.failure(TagReadError.unavailable))
                    return
                }
                s.alertMessage = alert
                self.session = s
                s.begin()
                DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
                    guard let self, self.session === s, self.isPending else { return }
                    s.alertMessage = String(localized: "Nothing detected yet. iPhone can't read bank cards, MIFARE Classic, or smart cards it doesn't recognize.")
                }
            }
        }
    }

    private var isPending: Bool {
        lock.lock()
        defer { lock.unlock() }
        return continuation != nil
    }

    private func finish(_ result: Result<TagReading, Error>) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(with: result)
    }

    // MARK: NFCTagReaderSessionDelegate

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        let mapped: TagReadError
        if let e = error as? NFCReaderError {
            switch e.code {
            case .readerSessionInvalidationErrorUserCanceled: mapped = .cancelled
            case .readerSessionInvalidationErrorSessionTimeout: mapped = .timeout
            case .readerSessionInvalidationErrorSystemIsBusy: mapped = .systemBusy
            default: mapped = .other(e.localizedDescription)
            }
        } else {
            mapped = .other(error.localizedDescription)
        }
        finish(.failure(mapped))
        self.session = nil
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        if tags.count > 1 {
            session.alertMessage = String(localized: "More than one tag. Hold just one.")
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { session.restartPolling() }
            return
        }
        guard let tag = tags.first else { return }
        let extended = extendedReads
        Task {
            do {
                try await session.connect(to: tag)
                let reading = try await Self.reading(from: tag, extended: extended)
                session.alertMessage = String(localized: "Read")
                self.finish(.success(reading))
                session.invalidate()
            } catch let e as TagReadError {
                self.finish(.failure(e))
                session.invalidate(errorMessage: String(localized: "This tag type isn't supported."))
            } catch {
                self.finish(.failure(TagReadError.moved))
                session.invalidate(errorMessage: String(localized: "Hold still and try again."))
            }
        }
    }

    // MARK: Identifier extraction

    static func reading(from tag: NFCTag, extended: Bool) async throws -> TagReading {
        switch tag {
        case .miFare(let t):
            let type: String
            switch t.mifareFamily {
            case .ultralight: type = "mifare_ultralight"
            case .desfire: type = "mifare_desfire"
            case .plus: type = "mifare_plus"
            default: type = "unknown"
            }
            var r = TagReading(family: .mifare, tagType: type, identifier: [UInt8](t.identifier))
            r.historicalBytes = t.historicalBytes.map { [UInt8]($0) }
            // NDEF first: a NAK to an optional command below (READ_CNT with the
            // counter disabled, GET_VERSION on older Ultralights) halts the tag.
            r.ndef = await ndef(t)
            if extended {
                if t.mifareFamily == .ultralight {
                    if let v = try? await t.sendMiFareCommand(commandPacket: Data([0x60])) {
                        r.chip = Uid.chipFromGetVersion([UInt8](v))
                    }
                    if !r.chip.isEmpty {
                        if let sig = try? await t.sendMiFareCommand(commandPacket: Data([0x3C, 0x00])), sig.count == 32 {
                            r.signature = [UInt8](sig)
                        }
                        if let c = try? await t.sendMiFareCommand(commandPacket: Data([0x39, 0x02])), c.count == 3 {
                            let b = [UInt8](c)
                            r.counter = Int(b[0]) | Int(b[1]) << 8 | Int(b[2]) << 16
                        }
                    }
                } else if t.mifareFamily == .desfire {
                    let apdu = NFCISO7816APDU(instructionClass: 0x90, instructionCode: 0x60, p1Parameter: 0, p2Parameter: 0,
                                              data: Data(), expectedResponseLength: 256)
                    if let response = try? await t.sendMiFareISO7816Command(apdu) {
                        r.chip = Uid.chipFromDesfireVersion([UInt8](response.0))
                    }
                }
            }
            return r

        case .iso15693(let t):
            var r = TagReading(family: .iso15693, tagType: "iso15693", identifier: [UInt8](t.identifier))
            if extended, let info = try? await t.systemInfo(requestFlags: [.highDataRate]) {
                if info.dataStorageFormatIdentifier >= 0 { r.dsfid = [UInt8(truncatingIfNeeded: info.dataStorageFormatIdentifier)] }
                if info.applicationFamilyIdentifier >= 0 { r.afi = [UInt8(truncatingIfNeeded: info.applicationFamilyIdentifier)] }
                if info.blockSize > 0 { r.blockSize = info.blockSize }
                if info.totalBlocks > 0 { r.blockCount = info.totalBlocks }
            }
            r.ndef = await ndef(t)
            return r

        case .feliCa(let t):
            var r = TagReading(family: .felica, tagType: "felica", identifier: [UInt8](t.currentIDm))
            r.systemCode = [UInt8](t.currentSystemCode)
            if extended, let polled = try? await t.polling(systemCode: t.currentSystemCode, requestCode: .noRequest, timeSlot: .max1) {
                r.pmm = [UInt8](polled.0)
            }
            r.ndef = await ndef(t)
            return r

        case .iso7816(let t):
            let isB = t.applicationData != nil
            var r = TagReading(family: isB ? .iso7816B : .iso7816A, tagType: "iso7816", identifier: [UInt8](t.identifier))
            r.historicalBytes = t.historicalBytes.map { [UInt8]($0) }
            r.applicationData = t.applicationData.map { [UInt8]($0) }
            r.ndef = await ndef(t)
            return r

        @unknown default:
            throw TagReadError.unsupported
        }
    }

    private static func ndef(_ t: NFCNDEFTag) async -> [NdefRecord] {
        guard let query = try? await t.queryNDEFStatus(), query.0 != .notSupported,
              let message = try? await t.readNDEF() else { return [] }
        return message.records.map {
            NdefRecord(tnf: Int($0.typeNameFormat.rawValue), type: [UInt8]($0.type), id: [UInt8]($0.identifier), payload: [UInt8]($0.payload))
        }
    }
}

/// Batch mode: one Core NFC session after another, tag after tag, until the
/// user stops. After each tag the session restarts polling instead of closing;
/// when the system ends a session at its 60-second limit, the next one begins
/// at once. A tag held against the phone is only reported once, however many
/// times polling finds it again.
@MainActor
final class BatchTagReader: NSObject, NFCTagReaderSessionDelegate {

    /// Called for every new tag, on the main actor.
    var onTag: ((TagReading) -> Void)?
    /// Called once when the batch ends on its own (Cancel on the sheet, NFC unavailable).
    var onEnd: ((TagReadError) -> Void)?

    private(set) var active = false
    private var session: NFCTagReaderSession?
    private var polling: NFCTagReaderSession.PollingOption = [.iso14443]
    private var extendedReads = true
    private var alert = ""
    private var lastKey: String?
    private var lastSeen = Date.distantPast
    private var fakeTask: Task<Void, Never>?
    /// Changes on every start and stop, so a restart scheduled for an earlier run never fires in a later one.
    private var runToken = 0
    /// Session restarts in a row that ended without reading a tag.
    private var emptyRestarts = 0

    /// Same-UID reads closer together than this are one tag held in place.
    /// Polling restarts about once a second, so a held tag keeps refreshing it.
    private static let holdWindow: TimeInterval = 3
    private static let maxEmptyRestarts = 3

    func start(technologies: [String], extendedReads: Bool, alert: String) {
        guard !active else { return }
        var p: NFCTagReaderSession.PollingOption = []
        if technologies.contains("iso14443") || technologies.contains("iso7816") { p.insert(.iso14443) }
        if technologies.contains("iso15693") { p.insert(.iso15693) }
        if technologies.contains("felica") { p.insert(.iso18092) }
        polling = p.isEmpty ? [.iso14443] : p
        self.extendedReads = extendedReads
        self.alert = alert
        lastKey = nil
        emptyRestarts = 0
        runToken += 1
        active = true
        #if targetEnvironment(simulator)
        fakeTask = Task { [weak self] in
            var n: UInt8 = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let self, self.active else { return }
                n &+= 1
                var r = TagReading(family: .mifare, tagType: "mifare_ultralight", identifier: [0x04, 0xA2, 0x7F, 0x1B, 0x5E, 0x80, n])
                r.chip = "NTAG215"
                self.onTag?(r)
            }
        }
        #else
        guard NFCTagReaderSession.readingAvailable else {
            active = false
            onEnd?(.unavailable)
            return
        }
        begin()
        #endif
    }

    /// Ends the batch from the app side. No onEnd callback.
    func stop() {
        guard active else { return }
        active = false
        runToken += 1
        fakeTask?.cancel()
        fakeTask = nil
        let s = session
        session = nil
        s?.invalidate()
    }

    func setAlert(_ text: String) {
        alert = text
        session?.alertMessage = text
    }

    private func begin() {
        // Typed optional, like CoreNFCTagReader: compiles whether or not the SDK imports this init as failable.
        let created: NFCTagReaderSession? = active ? NFCTagReaderSession(pollingOption: polling, delegate: self, queue: .main) : nil
        guard active, let s = created else {
            if active {
                active = false
                onEnd?(.unavailable)
            }
            return
        }
        s.alertMessage = alert
        session = s
        s.begin()
    }

    private func end(_ e: TagReadError) {
        guard active else { return }
        active = false
        session = nil
        onEnd?(e)
    }

    // MARK: NFCTagReaderSessionDelegate (delivered on the main queue)

    nonisolated func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        let code = (error as? NFCReaderError)?.code
        MainActor.assumeIsolated {
            guard session === self.session else { return }
            self.session = nil
            switch code {
            case .readerSessionInvalidationErrorSessionTimeout?, .readerSessionInvalidationErrorSessionTerminatedUnexpectedly?:
                // A timeout is the normal 60-second end; start the next session. Stop instead if the app
                // left the foreground or sessions keep dying without a single tag.
                self.emptyRestarts += 1
                guard UIApplication.shared.applicationState == .active, self.emptyRestarts <= Self.maxEmptyRestarts else {
                    self.end(.timeout)
                    return
                }
                let token = self.runToken
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard let self, self.runToken == token else { return }
                    self.begin()
                }
            case .readerSessionInvalidationErrorUserCanceled?:
                self.end(.cancelled)
            case .readerSessionInvalidationErrorSystemIsBusy?:
                self.end(.systemBusy)
            default:
                self.end(.other(error.localizedDescription))
            }
        }
    }

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        MainActor.assumeIsolated {
            guard session === self.session, self.active else { return }
            if tags.count > 1 {
                session.alertMessage = String(localized: "More than one tag. Hold just one.")
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    guard let self, self.active, session === self.session else { return }
                    session.alertMessage = self.alert
                    session.restartPolling()
                }
                return
            }
            guard let tag = tags.first else { return }
            let extended = self.extendedReads
            Task { @MainActor [weak self] in
                var reading: TagReading?
                do {
                    try await session.connect(to: tag)
                    reading = try await CoreNFCTagReader.reading(from: tag, extended: extended)
                } catch {
                    reading = nil
                }
                guard let self, self.active, session === self.session else { return }
                if let r = reading {
                    self.emptyRestarts = 0
                    // A random-ID tag shows a new UID on every read, so any random-ID read inside the
                    // window counts as the same tag held in place.
                    let random = r.identifier.count == 4 && r.identifier.first == 0x08
                    let key = random ? "random" : Encoding.hexLower(r.identifier)
                    let now = Date()
                    let held = key == self.lastKey && now.timeIntervalSince(self.lastSeen) < Self.holdWindow
                    self.lastKey = key
                    self.lastSeen = now
                    if !held { self.onTag?(r) }
                }
                try? await Task.sleep(nanoseconds: 800_000_000)
                guard self.active, session === self.session else { return }
                session.restartPolling()
            }
        }
    }
}
