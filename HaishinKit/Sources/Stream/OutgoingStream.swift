import AVFoundation
import Foundation

/// An object that provides a stream ingest feature.
package final class OutgoingStream {
    package private(set) var isRunning = false

    /// The asynchronous sequence for audio output.
    package var audioOutputStream: AsyncStream<(AVAudioBuffer, AVAudioTime)> {
        return audioCodec.outputStream
    }

    /// Specifies the audio compression properties.
    package var audioSettings: AudioCodecSettings {
        get {
            audioCodec.settings
        }
        set {
            audioCodec.settings = newValue
        }
    }

    /// The audio input format.
    package private(set) var audioInputFormat: CMFormatDescription?

    /// A hook onto the COMPRESSED video access units, between the encoder and the muxer.
    ///
    /// TVC fork addition. HaishinKit's public surface stops at `videoSettings` and `StreamOutput`,
    /// which carry raw/preview sample buffers — there is no way for an application to see, count or
    /// modify what the VideoToolbox encoder actually produced. Two things need exactly that:
    ///
    /// 1. **Encoder statistics.** "Is the encoder meeting its target?" cannot be answered from
    ///    egress: a still scene encodes small on a perfect link, and a congested link carries a
    ///    healthy encoder's output badly. Only the encoded AUs say what the encoder produced.
    /// 2. **Capture-timestamp SEI.** Stamping each AU with its sensor capture time needs a splice
    ///    point on the compressed bitstream (the Android RootEncoder fork calls its equivalent hook
    ///    `videoDataTransformer`, and this deliberately shares the name).
    ///
    /// Return the buffer unchanged to observe, a new buffer to replace it, or nil to drop it.
    /// Called on the task that drains the encoder, once per encoded access unit. Nil transformer
    /// (the default) leaves the original sequence completely untouched — no extra task, no copy.
    package var videoDataTransformer: (@Sendable (CMSampleBuffer) -> CMSampleBuffer?)?

    /// The asynchronous sequence for video output.
    package var videoOutputStream: AsyncStream<CMSampleBuffer> {
        // `videoCodec.outputStream` re-creates the sequence and re-assigns the codec's continuation
        // on every access, so it must be read exactly once here.
        let source = videoCodec.outputStream
        guard let transform = videoDataTransformer else {
            return source
        }
        return AsyncStream { continuation in
            let task = Task {
                for await buffer in source {
                    if let out = transform(buffer) {
                        continuation.yield(out)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Specifies the video compression properties.
    package var videoSettings: VideoCodecSettings {
        get {
            videoCodec.settings
        }
        set {
            videoCodec.settings = newValue
        }
    }

    /// Specifies the video buffering count.
    package var videoInputBufferCounts = -1

    /// The asynchronous sequence for video input buffer.
    package var videoInputStream: AsyncStream<CMSampleBuffer> {
        if 0 < videoInputBufferCounts {
            return AsyncStream(CMSampleBuffer.self, bufferingPolicy: .bufferingNewest(videoInputBufferCounts)) { continuation in
                self.videoInputContinuation = continuation
            }
        } else {
            return AsyncStream { continuation in
                self.videoInputContinuation = continuation
            }
        }
    }

    /// The video input format.
    package private(set) var videoInputFormat: CMFormatDescription?

    private var audioCodec = AudioCodec()
    private var videoCodec = VideoCodec()
    private var videoInputContinuation: AsyncStream<CMSampleBuffer>.Continuation? {
        didSet {
            oldValue?.finish()
        }
    }

    /// Create a new instance.
    package init() {
    }

    /// Appends a sample buffer for publish.
    package func append(_ sampleBuffer: CMSampleBuffer) {
        switch sampleBuffer.formatDescription?.mediaType {
        case .audio:
            audioInputFormat = sampleBuffer.formatDescription
            audioCodec.append(sampleBuffer)
        case .video:
            videoInputFormat = sampleBuffer.formatDescription
            videoInputContinuation?.yield(sampleBuffer)
        default:
            break
        }
    }

    /// Appends a sample buffer for publish.
    package func append(_ audioBuffer: AVAudioBuffer, when: AVAudioTime) {
        audioInputFormat = audioBuffer.format.formatDescription
        audioCodec.append(audioBuffer, when: when)
    }

    /// Appends a video buffer.
    package func append(video sampleBuffer: CMSampleBuffer) {
        videoCodec.append(sampleBuffer)
    }
}

extension OutgoingStream: Runner {
    // MARK: Runner
    package func startRunning() {
        guard !isRunning else {
            return
        }
        videoCodec.startRunning()
        audioCodec.startRunning()
        isRunning = true
    }

    package func stopRunning() {
        guard isRunning else {
            return
        }
        isRunning = false
        videoCodec.stopRunning()
        audioCodec.stopRunning()
        videoInputContinuation = nil
    }
}
