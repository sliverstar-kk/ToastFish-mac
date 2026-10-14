import AVFoundation
import ToastFishCore

/// Bridges study sessions to macOS notifications and speech.
@MainActor
final class NotificationPresenter: StudyPresenter {
    private let notifications: NotificationService
    private let synthesizer = AVSpeechSynthesizer()

    init(notifications: NotificationService) {
        self.notifications = notifications
    }

    func ask(_ prompt: StudyPrompt) async -> String? {
        await notifications.ask(prompt)
    }

    func show(_ message: String) {
        notifications.post(title: "ToastFish", body: message)
    }

    func pause(seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    /// System TTS for now; downloaded Youdao audio comes with the pronunciation goal.
    func pronounce(_ word: Word, engType: Int) {
        let utterance = AVSpeechUtterance(string: word.headWord)
        utterance.voice = AVSpeechSynthesisVoice(language: engType == 1 ? "en-US" : "en-GB")
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }
}
