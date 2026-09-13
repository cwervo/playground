import AVFoundation
import Foundation

/// Loops one second of generated silence at zero volume. With the `audio`
/// background mode this keeps the process scheduled while PiP is up, so the
/// refresh timer keeps firing even on long intervals.
final class SilentAudioKeeper {
    private var player: AVAudioPlayer?

    func start() {
        guard player == nil else { return }
        guard let url = Self.silentWAVURL() else { return }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = 0
            p.prepareToPlay()
            p.play()
            player = p
        } catch {
            print("SilentAudioKeeper: \(error)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
    }

    /// Writes a 1 s, 8 kHz, 16-bit mono WAV of zeros to the temp directory.
    private static func silentWAVURL() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("silence.wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }

        let sampleRate: UInt32 = 8000
        let seconds: UInt32 = 1
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let blockAlign = channels * bitsPerSample / 8
        let byteRate = sampleRate * UInt32(blockAlign)
        let dataSize = sampleRate * seconds * UInt32(blockAlign)

        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))            // PCM
        append(channels)
        append(sampleRate)
        append(byteRate)
        append(blockAlign)
        append(bitsPerSample)
        data.append(contentsOf: Array("data".utf8))
        append(dataSize)
        data.append(Data(count: Int(dataSize)))

        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            print("SilentAudioKeeper: \(error)")
            return nil
        }
    }
}
