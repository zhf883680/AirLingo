import AVFoundation

/// 朗读：走系统 TTS。
enum Speaker {
    private static let synthesizer = AVSpeechSynthesizer()

    static func speak(_ text: String, language: String, rate: Double = 1.0) {
        guard !text.isEmpty else { return }
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
            ?? AVSpeechSynthesisVoice(language: AppLanguage.base(language))
        utterance.rate = Float(AVSpeechUtteranceDefaultSpeechRate) * Float(max(0.3, min(2.0, rate)))
        synthesizer.speak(utterance)
    }
}
