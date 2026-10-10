import AVFoundation

/// The short "tick" the original iPod's piezo speaker made as the wheel turned.
/// Synthesized once into a tiny buffer so it can be retriggered quickly.
final class ClickSound {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let buffer: AVAudioPCMBuffer

    init() {
        let sampleRate = 44_100.0
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frames: AVAudioFrameCount = 360
        buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            let t = Float(i)
            let envelope = expf(-t / 28)
            let tone = sinf(2 * .pi * 3_200 * t / Float(sampleRate))
            let noise = Float.random(in: -1...1)
            samples[i] = (0.55 * tone + 0.45 * noise) * envelope * 0.55
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    func play() {
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        node.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !node.isPlaying { node.play() }
    }
}
