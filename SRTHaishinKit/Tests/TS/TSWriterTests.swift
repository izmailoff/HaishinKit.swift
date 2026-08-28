import AVFoundation
import CoreMedia
import Foundation
import Testing

@testable import SRTHaishinKit

@Suite struct TSWriterTests {
    /// An H.264 format description at the given size — what a VTCompressionSession rebuilt at a
    /// new `videoSize` hands the writer. Between resolution rungs only the dimensions differ.
    private static func makeH264Format(width: Int32, height: Int32) -> CMFormatDescription? {
        var format: CMFormatDescription?
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCMVideoCodecType_H264,
            width: width,
            height: height,
            extensions: nil,
            formatDescriptionOut: &format
        )
        return format
    }

    private static func makeAACFormat(sampleRate: Double) -> AVAudioFormat? {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: 1024,
            mBytesPerFrame: 0,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 0,
            mReserved: 0
        )
        return AVAudioFormat(streamDescription: &asbd)
    }

    /// The PMT inside one program write (PAT packet + PMT packet, 188 bytes each).
    private static func parsePMT(_ data: Data) -> TSProgramMap? {
        for offset in stride(from: 0, to: data.count, by: TSPacket.size) {
            guard offset + TSPacket.size <= data.count,
                  let packet = TSPacket(data: data.subdata(in: offset..<offset + TSPacket.size)),
                  packet.pid == TSWriter.defaultPMTPID else {
                continue
            }
            return TSProgramMap(packet.payload)
        }
        return nil
    }

    private static func rows(_ pmt: TSProgramMap, for pid: UInt16) -> [ESSpecificData] {
        pmt.elementaryStreamSpecificData.filter { $0.elementaryPID == pid }
    }

    @Test func videoFormatChangeKeepsOneRowPerPID() async throws {
        let writer = TSWriter()
        writer.expectedMedias = [.video]
        var output = writer.output.makeAsyncIterator()

        let format1080 = try #require(Self.makeH264Format(width: 1920, height: 1080))
        let format720 = try #require(Self.makeH264Format(width: 1280, height: 720))
        #expect(format1080 != format720)

        writer.videoFormat = format1080
        let firstWrite = await output.next()
        let firstPMT = try #require(Self.parsePMT(firstWrite ?? Data()))
        #expect(Self.rows(firstPMT, for: TSWriter.defaultVideoPID).count == 1)

        // The adaptive-resolution rung swap: a new session, a new format description, same PID.
        writer.videoFormat = format720

        let videoRows = Self.rows(writer.pmt, for: TSWriter.defaultVideoPID)
        #expect(videoRows.count == 1)
        #expect(videoRows.first?.streamType == .h264)
        #expect(writer.pmt.elementaryStreamSpecificData.count == 1)

        // The change is followed by a PMT rewrite, and what goes on the wire has one row too.
        let secondWrite = await output.next()
        let secondPMT = try #require(Self.parsePMT(secondWrite ?? Data()))
        #expect(Self.rows(secondPMT, for: TSWriter.defaultVideoPID).count == 1)
        #expect(secondPMT.elementaryStreamSpecificData.count == 1)
    }

    @Test func videoFormatChangeLeavesAudioRowAlone() async throws {
        let writer = TSWriter()
        writer.expectedMedias = [.audio, .video]
        var output = writer.output.makeAsyncIterator()

        let aac = try #require(Self.makeAACFormat(sampleRate: 48_000))
        let format1080 = try #require(Self.makeH264Format(width: 1920, height: 1080))
        let format540 = try #require(Self.makeH264Format(width: 960, height: 540))

        writer.audioFormat = aac
        writer.videoFormat = format1080
        _ = await output.next()

        writer.videoFormat = format540

        // Replacement is keyed by PID: the audio row is not the one being replaced.
        #expect(writer.pmt.elementaryStreamSpecificData.count == 2)
        let audioRows = Self.rows(writer.pmt, for: TSWriter.defaultAudioPID)
        #expect(audioRows.count == 1)
        #expect(audioRows.first?.streamType == .adtsAac)
        let videoRows = Self.rows(writer.pmt, for: TSWriter.defaultVideoPID)
        #expect(videoRows.count == 1)
        #expect(videoRows.first?.streamType == .h264)

        let rewrite = await output.next()
        let pmt = try #require(Self.parsePMT(rewrite ?? Data()))
        #expect(pmt.elementaryStreamSpecificData.count == 2)
    }

    @Test func audioFormatChangeKeepsOneRowPerPID() async throws {
        let writer = TSWriter()
        writer.expectedMedias = [.audio]
        var output = writer.output.makeAsyncIterator()

        let aac48 = try #require(Self.makeAACFormat(sampleRate: 48_000))
        let aac44 = try #require(Self.makeAACFormat(sampleRate: 44_100))
        #expect(aac48 != aac44)

        writer.audioFormat = aac48
        _ = await output.next()
        writer.audioFormat = aac44

        let audioRows = Self.rows(writer.pmt, for: TSWriter.defaultAudioPID)
        #expect(audioRows.count == 1)
        #expect(writer.pmt.elementaryStreamSpecificData.count == 1)

        let rewrite = await output.next()
        let pmt = try #require(Self.parsePMT(rewrite ?? Data()))
        #expect(Self.rows(pmt, for: TSWriter.defaultAudioPID).count == 1)
    }
}
