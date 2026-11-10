import AVFoundation
import Foundation

/// Plays a native speaker recording of a word from JapanesePod101's public
/// dictionary audio (the same source Yomitan uses by default). Needs internet.
@MainActor
final class WordAudio {
    static let shared = WordAudio()
    private var player: AVAudioPlayer?
    /// Counts the words played, so only the last one gives the sound back.
    private var turn = 0
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
            let session = AVAudioSession.sharedInstance()
            // Music or a podcast playing in another app is lowered for the
            // length of the word, not stopped.
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(data: data)
            self.player = player
            player.play()
            turn += 1
            let mine = turn
            let length = player.duration
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(length + 0.25))
                self?.finished(mine)
            }
            return .played
        } catch {
            return .failed
        }
    }

    /// The word is over: hand the sound back, so the music returns to full volume.
    private func finished(_ finishedTurn: Int) {
        guard finishedTurn == turn, player?.isPlaying != true else { return }
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
