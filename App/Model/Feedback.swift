import AudioToolbox
import AVFoundation
import TapPonyKit
import UIKit

/// Sound, haptics and speech after a scan. Core NFC already plays its own
/// sound and vibration when a tag is read; these report how the send went.
@MainActor
final class Feedback: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    /// The system's positive and negative acknowledgement tones. They follow the
    /// ring/silent switch like any system sound.
    func tone(ok: Bool) {
        AudioServicesPlaySystemSound(ok ? 1054 : 1053)
    }

    func haptic(ok: Bool) {
        let g = UINotificationFeedbackGenerator()
        g.notificationOccurred(ok ? .success : .error)
    }

    /// Spoken confirmation for hands-free rounds (PROFILE_SCHEMA.md section 15),
    /// with the phone's own voice. Nothing leaves the device.
    func speak(_ text: String) {
        let t = Encoding.capCodePoints(text.trimmingCharacters(in: .whitespacesAndNewlines), 200)
        guard !t.isEmpty else { return }
        let u = AVSpeechUtterance(string: t)
        u.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        // Spoken results are for hands-free rounds: play even on silent, and duck music instead of stopping it.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        synth.speak(u)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        releaseAudio(synthesizer)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        releaseAudio(synthesizer)
    }

    /// Hands the audio back to whatever was playing once nothing is left to say.
    private nonisolated func releaseAudio(_ synthesizer: AVSpeechSynthesizer) {
        guard !synthesizer.isSpeaking else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// What to say: the result text, else the server message, else a short word.
    static func spoken(_ o: ScanOutcome) -> String {
        if let t = o.resultText { return t }
        if let m = o.message { return m }
        if o.queued { return String(localized: "Saved for later") }
        return o.result?.ok == true ? String(localized: "Sent") : String(localized: "Failed")
    }

    /// Plays whatever the profiles ask for after one tag's sends finish.
    func after(_ results: [(Profile, ScanOutcome)]) {
        let ok = results.allSatisfy { $0.1.queued || $0.1.result?.ok == true }
        if results.contains(where: { $0.0.after.sound }) { tone(ok: ok) }
        if results.contains(where: { $0.0.after.haptic }) { haptic(ok: ok) }
        for (p, o) in results where p.after.speak && Entitlements.responseRules { speak(Self.spoken(o)) }
    }
}
