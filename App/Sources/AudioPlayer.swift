import AVFoundation
import Foundation

/// Plays a native speaker recording of a word from JapanesePod101's public
/// dictionary audio (the same source Yomitan uses by default). Needs internet.
@MainActor
final class WordAudio {
    static let shared = WordAudio()
    private var player: AVAudioPlayer?
    /// JapanesePod101 answers unknown words with this "not available" clip.
    private let missingClipSize = 52288

    enum Result { case played, notFound, failed }

    func play(expression: String, reading: String) async -> Result {
        var c = URLComponents(string: "https://assets.languagepod101.com/dictionary/japanese/audiomp3.php")!
        c.queryItems = [URLQueryItem(name: "kanji", value: expression), URLQueryItem(name: "kana", value: reading)]
        guard let url = c.url else { return .failed }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard data.count != missingClipSize, data.count > 1000 else { return .notFound }
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(data: data)
            player?.play()
            return .played
        } catch {
            return .failed
        }
    }
}
