import AVFoundation
import ToastFishCore

/// Bridges study sessions to macOS notifications and speech.
@MainActor
final class NotificationPresenter: StudyPresenter {
    private let notifications: NotificationService
    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?

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

    func speakJapanese(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        player?.stop()
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }

    func playGoin(_ romaji: String) {
        // The bundled recordings use Kunrei spellings for these three kana.
        let file = ["chi": "ci", "tsu": "cu", "fu": "hu"][romaji] ?? romaji
        guard let url = Bundle.main.url(forResource: file, withExtension: "mp3", subdirectory: "Goin") else { return }
        synthesizer.stopSpeaking(at: .immediate)
        player?.stop()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }

    /// Whether a Japanese voice is installed (the original warned when it wasn't).
    static var hasJapaneseVoice: Bool {
        AVSpeechSynthesisVoice.speechVoices().contains { $0.language == "ja-JP" }
    }
}
