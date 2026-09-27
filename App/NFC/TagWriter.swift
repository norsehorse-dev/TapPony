import CoreNFC
import Foundation
import TapPonyKit

/// What to write. Mirror UID is filled in from the tag itself at write time.
enum WriteJob: Equatable {
    case url(String)
    case text(String)
    case mirrorUid
    case launch(token: String, label: String, profileId: String?)
}

/// Why a write failed. The Tags tab has copy for each.
struct WriteError: Error, Equatable {
    let code: String
    /// Set for lockFailed: the write itself landed on this tag (canonical UID, empty when random).
    var uid: String? = nil
}

/// Writes one NDEF message with a Core NFC tag session: read the tag's
/// identity, write, optionally lock (permanent), close. Returns the tag's
/// canonical UID, empty when it is random.
@MainActor
final class TagWriter: NSObject, NFCTagReaderSessionDelegate {

    private var continuation: CheckedContinuation<String, Error>?
    private var session: NFCTagReaderSession?
    private var job: WriteJob = .mirrorUid
    private var lock = false

    func write(_ job: WriteJob, lock: Bool) async throws -> String {
        #if targetEnvironment(simulator)
        try await Task.sleep(nanoseconds: 500_000_000)
        return "04A27F1B5E8000"
        #else
        guard NFCTagReaderSession.readingAvailable else { throw WriteError(code: "unavailable") }
        self.job = job
        self.lock = lock
        return try await withCheckedThrowingContinuation { cont in
            continuation = cont
            let created: NFCTagReaderSession? = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693], delegate: self, queue: .main)
            guard let s = created else {
                finish(.failure(WriteError(code: "unavailable")))
                return
            }
            s.alertMessage = String(localized: "Hold the tag to write")
            session = s
            s.begin()
        }
        #endif
    }

    private func finish(_ r: Result<String, Error>) {
        let c = continuation
        continuation = nil
        c?.resume(with: r)
    }

    // MARK: NFCTagReaderSessionDelegate (delivered on the main queue)

    nonisolated func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        let code = (error as? NFCReaderError)?.code
        MainActor.assumeIsolated {
            guard session === self.session else { return }
            self.session = nil
            switch code {
            case .readerSessionInvalidationErrorUserCanceled?: self.finish(.failure(WriteError(code: "cancelled")))
            case .readerSessionInvalidationErrorSessionTimeout?: self.finish(.failure(WriteError(code: "timeout")))
            default: self.finish(.failure(WriteError(code: "failed")))
            }
        }
    }

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        MainActor.assumeIsolated {
            guard session === self.session else { return }
            if tags.count > 1 {
                session.alertMessage = String(localized: "More than one tag. Hold just one.")
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    session.restartPolling()
                }
                return
            }
            guard let tag = tags.first else { return }
            let job = self.job
            let lock = self.lock
            Task { @MainActor [weak self] in
                let result: Result<String, Error>
                do {
                    try await session.connect(to: tag)
                    let uid = try await Self.perform(job, lock: lock, on: tag)
                    session.alertMessage = lock ? String(localized: "Written and locked") : String(localized: "Written")
                    session.invalidate()
                    result = .success(uid)
                } catch let e as WriteError {
                    session.invalidate(errorMessage: Self.shortText(e.code))
                    result = .failure(e)
                } catch {
                    session.invalidate(errorMessage: Self.shortText("moved"))
                    result = .failure(WriteError(code: "moved"))
                }
                // The user may have cancelled meanwhile (already finished) and even
                // started a new write; never touch that newer session or continuation.
                guard let self, self.session === session else { return }
                self.session = nil
                self.finish(result)
            }
        }
    }

    private static func perform(_ job: WriteJob, lock: Bool, on tag: NFCTag) async throws -> String {
        let reading = try await CoreNFCTagReader.reading(from: tag, extended: false)
        let ids = Variables.build(reading, SendContext(scanTimeMs: 0, sendTimeMs: 0, timeZone: "UTC", profileName: "", profileId: "",
                                                       deviceLabel: "", platform: "ios", nonce: "", seq: 0))
        let uid = ids["random_uid"] == "true" ? "" : (ids["uid"] ?? "")
        let payload: NFCNDEFPayload?
        switch job {
        case .url(let s):
            payload = Self.uriPayload(s)
        case .text(let s):
            payload = NFCNDEFPayload.wellKnownTypeTextPayload(string: s, locale: Locale(identifier: "en"))
        case .mirrorUid:
            guard !uid.isEmpty else { throw WriteError(code: "randomUid") }
            payload = NFCNDEFPayload.wellKnownTypeTextPayload(string: uid, locale: Locale(identifier: "en"))
        case .launch(let token, _, _):
            payload = Self.uriPayload(Tags.link(token))
        }
        guard let payload else { throw WriteError(code: "failed") }
        let message = NFCNDEFMessage(records: [payload])

        let ndefTag: NFCNDEFTag
        switch tag {
        case .miFare(let t): ndefTag = t
        case .iso15693(let t): ndefTag = t
        case .feliCa(let t): ndefTag = t
        case .iso7816(let t): ndefTag = t
        @unknown default: throw WriteError(code: "notNdef")
        }
        let (status, capacity) = try await ndefTag.queryNDEFStatus()
        switch status {
        case .notSupported: throw WriteError(code: "notNdef")
        case .readOnly: throw WriteError(code: "readOnly")
        default: break
        }
        if message.length > capacity { throw WriteError(code: "tooSmall") }
        try await ndefTag.writeNDEF(message)
        if lock {
            do {
                try await ndefTag.writeLock()
            } catch {
                throw WriteError(code: "lockFailed", uid: uid)
            }
        }
        return uid
    }

    /// A well-known URI record built by the shared kit, so the prefix code is the
    /// one section 16 pins (0x04 for launch links) and matches Android byte for byte.
    private static func uriPayload(_ uri: String) -> NFCNDEFPayload {
        let r = Ndef.uriRecord(uri)
        return NFCNDEFPayload(format: .nfcWellKnown, type: Data(r.type), identifier: Data(r.id), payload: Data(r.payload))
    }

    /// One line for the system sheet; the Tags tab shows the full sentence.
    nonisolated static func shortText(_ code: String) -> String {
        switch code {
        case "readOnly": return String(localized: "This tag is locked.")
        case "tooSmall": return String(localized: "Not enough room on this tag.")
        case "notNdef": return String(localized: "This tag can't hold NDEF content.")
        case "randomUid": return String(localized: "This tag has no fixed UID.")
        case "lockFailed": return String(localized: "Written, but locking failed.")
        default: return String(localized: "Hold still and try again.")
        }
    }
}
