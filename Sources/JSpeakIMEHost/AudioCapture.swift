@preconcurrency import AVFoundation
import Foundation

final class AudioCapture {
    private let engine = AVAudioEngine()
    private let targetFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var data = Data()
    private var chunkData = Data()
    private let chunkQueue = DispatchQueue(label: "jspeak.audio.chunk")
    private var onChunk: ((Data) -> Void)?

    // 500ms at 16kHz mono s16le = 0.5 * 16000 * 2 = 16000 bytes
    private let chunkBytesTarget = 16000

    init() {
        targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    }

    func start(onChunk: ((Data) -> Void)? = nil) throws {
        data = Data()
        chunkData = Data()
        self.onChunk = onChunk
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            let bufferCopy = buffer
            guard let self, let converter = self.converter else { return }

            let ratio = self.targetFormat.sampleRate / inputFormat.sampleRate
            let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1)
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: outCapacity) else { return }

            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return bufferCopy
            }
            converter.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)
            if error != nil { return }

            guard let channel = outBuffer.int16ChannelData else { return }
            let count = Int(outBuffer.frameLength)
            let byteCount = count * MemoryLayout<Int16>.size
            let chunk = Data(bytes: channel.pointee, count: byteCount)
            self.data.append(chunk)

            if let handler = self.onChunk {
                self.chunkQueue.async {
                    self.chunkData.append(chunk)
                    if self.chunkData.count >= self.chunkBytesTarget {
                        let out = self.chunkData
                        self.chunkData = Data()
                        handler(out)
                    }
                }
            }
        }

        engine.prepare()
        try engine.start()
    }

    func stop() -> Data {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        // Do not emit remaining chunk from here; let the caller decide when to push.
        onChunk = nil

        let byteCount = data.count
        var rms: Double = 0
        if byteCount >= 2 {
            data.withUnsafeBytes { raw in
                let samples = raw.bindMemory(to: Int16.self)
                if samples.count > 0 {
                    var sum: Double = 0
                    for s in samples {
                        let v = Double(s) / 32768.0
                        sum += v * v
                    }
                    rms = (sum / Double(samples.count)).squareRoot()
                }
            }
        }
        NSLog("JSpeakAgent: pcm bytes=\(byteCount) rms=\(rms)")

        return data
    }

    func drainTrailingChunk() -> Data {
        chunkQueue.sync {
            let out = chunkData
            chunkData = Data()
            return out
        }
    }
}
