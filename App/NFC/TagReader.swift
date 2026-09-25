import CoreNFC
import Foundation
import TapPonyKit

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
            }
        }
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
