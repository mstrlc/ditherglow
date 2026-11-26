#!/usr/bin/env swift
// Turns a real Live Photo into the reference the iOS app's Live Photo export borrows from, for when a new iOS
// starts rejecting Ditherglow's Live Photo wallpapers. Take a Live Photo with the iPhone camera, check it works
// as a live wallpaper, copy it to the Mac with Image Capture (which keeps the HEIC and MOV pair intact), then:
//
//   scripts/live-photo-reference.swift IMG_1234.HEIC IMG_1234.MOV
//
// It writes Ditherglow/iOS/LivePhotoReference/LivePhotoReference.{mov,heic,json}: the video's metadata tracks,
// top-level keys and audio format (silenced), the photo's metadata on a blank image, and the frame timing.
// The picture, the sound, the location, capture-date keys and identifiers are dropped or replaced.
// Ported from livewall's `reference` command (https://github.com/dsablic/livewall, MIT).
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let droppedKeys: Set<String> = [
    "com.apple.quicktime.content.identifier",
    "com.apple.quicktime.location.ISO6709",
    "com.apple.quicktime.location.accuracy.horizontal",
    "com.apple.quicktime.creationdate",
]
let timescale: CMTimeScale = 600

struct Reference: Encodable {
    var frames: [Int64]
    var timescale: Int32
    var duration: Int64
    var still: Int64
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("live-photo-reference: \(message)\n".utf8))
    exit(1)
}

func scaled(_ time: CMTime) -> Int64 {
    CMTimeConvertScale(time, timescale: timescale, method: .roundHalfAwayFromZero).value
}

/// The same sample with every byte zeroed: the camera's own audio format, without the sound.
func silenced(_ sample: CMSampleBuffer) -> CMSampleBuffer {
    guard let source = CMSampleBufferGetDataBuffer(sample) else { return sample }
    let length = CMBlockBufferGetDataLength(source)
    var block: CMBlockBuffer?
    guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: length, blockAllocator: nil,
                                             customBlockSource: nil, offsetToData: 0, dataLength: length,
                                             flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block) == noErr,
        let block, CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: length) == noErr
    else { fail("can't silence the audio") }
    var timingCount: CMItemCount = 0
    CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &timingCount)
    var timing = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: timingCount)
    CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: timingCount, arrayToFill: &timing, entriesNeededOut: nil)
    var sizeCount: CMItemCount = 0
    CMSampleBufferGetSampleSizeArray(sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &sizeCount)
    var sizes = [Int](repeating: 0, count: sizeCount)
    CMSampleBufferGetSampleSizeArray(sample, entryCount: sizeCount, arrayToFill: &sizes, entriesNeededOut: nil)
    var out: CMSampleBuffer?
    guard CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: CMSampleBufferGetFormatDescription(sample),
                                    sampleCount: CMSampleBufferGetNumSamples(sample), sampleTimingEntryCount: timingCount,
                                    sampleTimingArray: &timing, sampleSizeEntryCount: sizeCount, sampleSizeArray: &sizes,
                                    sampleBufferOut: &out) == noErr, let out
    else { fail("can't silence the audio") }
    return out
}

func makeReference(photo: URL, movie: URL, into folder: URL) async throws {
    let asset = AVURLAsset(url: movie)
    guard let video = try await asset.loadTracks(withMediaType: .video).first else { fail("no video in \(movie.lastPathComponent)") }
    let duration = try await asset.load(.duration)

    // Frame times, which the app's frames are placed on so each live-photo-info sample lines up with one.
    let frameReader = try AVAssetReader(asset: asset)
    let frameOutput = AVAssetReaderTrackOutput(track: video, outputSettings: nil)
    frameReader.add(frameOutput)
    frameReader.startReading()
    var frames: [Int64] = []
    while let sample = frameOutput.copyNextSampleBuffer() {
        guard CMSampleBufferGetNumSamples(sample) > 0 else { continue }
        frames.append(scaled(CMSampleBufferGetPresentationTimeStamp(sample)))
    }
    frames.sort()

    // The camera places the still-image-time sample with an edit list, so its time is where that track's media starts.
    var still: Int64?
    for track in try await asset.loadTracks(withMediaType: .metadata) {
        let keys = try await track.load(.formatDescriptions).flatMap { CMMetadataFormatDescriptionGetIdentifiers($0) as? [String] ?? [] }
        guard keys.contains("mdta/com.apple.quicktime.still-image-time"),
              let placed = try await track.load(.segments).first(where: { !$0.isEmpty }) else { continue }
        still = scaled(placed.timeMapping.target.start)
    }
    guard let still else { fail("no still-image-time track: is \(movie.lastPathComponent) a Live Photo's video?") }

    // The movie: silenced audio, every metadata track, and the top-level keys bar location, date and identifier.
    let movieURL = folder.appendingPathComponent("LivePhotoReference.mov")
    try? FileManager.default.removeItem(at: movieURL)
    let writer = try AVAssetWriter(outputURL: movieURL, fileType: .mov)
    let reader = try AVAssetReader(asset: asset)
    var copies: [(input: AVAssetWriterInput, output: AVAssetReaderTrackOutput, isAudio: Bool)] = []
    for type in [AVMediaType.audio, .metadata] {
        for track in try await asset.loadTracks(withMediaType: type) {
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            reader.add(output)
            let input = try await AVAssetWriterInput(mediaType: type, outputSettings: nil, sourceFormatHint: track.load(.formatDescriptions).first)
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            copies.append((input, output, type == .audio))
        }
    }
    writer.metadata = try await asset.loadMetadata(for: .quickTimeMetadata).filter { !droppedKeys.contains($0.key as? String ?? "") }
    guard writer.startWriting(), reader.startReading() else { fail("can't copy \(movie.lastPathComponent)") }
    writer.startSession(atSourceTime: .zero)
    var finished = Array(repeating: false, count: copies.count)
    while finished.contains(false) {
        var progressed = false
        for (i, copy) in copies.enumerated() where !finished[i] {
            while copy.input.isReadyForMoreMediaData {
                guard let sample = copy.output.copyNextSampleBuffer() else {
                    copy.input.markAsFinished()
                    finished[i] = true
                    break
                }
                guard copy.input.append(copy.isAudio ? silenced(sample) : sample) else { fail("can't write \(movieURL.lastPathComponent)") }
                progressed = true
            }
        }
        if !progressed { try await Task.sleep(for: .milliseconds(2)) }
    }
    writer.endSession(atSourceTime: duration)
    await writer.finishWriting()
    guard writer.status == .completed else { fail("can't write \(movieURL.lastPathComponent): \(writer.error?.localizedDescription ?? "")") }

    // The photo's metadata on a blank 4 × 3 image, without location, the content identifier (tag 17) or per-capture UUIDs.
    guard let source = CGImageSourceCreateWithURL(photo as CFURL, nil),
          var properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { fail("can't read \(photo.lastPathComponent)") }
    for key in [kCGImagePropertyGPSDictionary, kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight, kCGImagePropertyDepth,
                kCGImagePropertyColorModel, kCGImagePropertyProfileName, kCGImagePropertyHasAlpha]
    {
        properties.removeValue(forKey: key)
    }
    if var maker = properties[kCGImagePropertyMakerAppleDictionary] as? [String: Any] {
        maker.removeValue(forKey: "17")
        for tag in ["11", "43"] where maker[tag] != nil {
            maker[tag] = UUID().uuidString
        }
        properties[kCGImagePropertyMakerAppleDictionary] = maker
    }
    let photoURL = folder.appendingPathComponent("LivePhotoReference.heic")
    guard let context = CGContext(data: nil, width: 4, height: 3, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
        let blank = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(photoURL as CFURL, UTType.heic.identifier as CFString, 1, nil)
    else { fail("can't write \(photoURL.lastPathComponent)") }
    CGImageDestinationAddImage(destination, blank, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { fail("can't write \(photoURL.lastPathComponent)") }

    let reference = Reference(frames: frames, timescale: timescale, duration: scaled(duration), still: still)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(reference).write(to: folder.appendingPathComponent("LivePhotoReference.json"))
    print("\(frames.count) frames over \(String(format: "%.2f", duration.seconds)) s, still at \(Double(still) / Double(timescale)) s → \(folder.path)")
}

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count == 2 else { fail("usage: live-photo-reference.swift <camera.HEIC> <camera.MOV>") }
let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Ditherglow/iOS/LivePhotoReference")
try await makeReference(photo: URL(fileURLWithPath: arguments[arguments.startIndex]),
                        movie: URL(fileURLWithPath: arguments[arguments.startIndex + 1]), into: folder)
