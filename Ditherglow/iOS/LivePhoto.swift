import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers
import VideoToolbox

/// A Live Photo of the sky drifting, saved to Photos, for an animated lock screen: iOS plays a Live Photo
/// wallpaper's motion each time the phone wakes.
///
/// A Live Photo is a still and a short movie sharing a content identifier. That is enough for Photos, but the
/// lock screen silently checks much more and calls anything else "not supported". Apple documents none of it;
/// this follows livewall's recipe (https://github.com/dsablic/livewall), each part found on a device:
/// - the movie carries a real capture's metadata tracks, top-level keys and (silenced) audio, borrowed from
///   the bundled `LivePhotoReference.mov`, with our frames placed on that capture's exact frame times;
/// - the movie is HEVC stored sideways, 1920 × 1440, with a 90° playback transform, as the camera writes it;
/// - the still is the movie's frame at the reference's still time, stored sideways too and tagged to rotate,
///   carrying the reference photo's EXIF and maker notes;
/// - the movie is HDR: 10-bit HLG, as the camera's is. An 8-bit SDR movie was rejected outright, and a 10-bit SDR one
///   was accepted but never moved. The still is HLG too, written with a gain map as the camera writes HDR photos.
nonisolated enum LivePhoto {
    /// Animation-time units per second. Much faster than the wallpaper's drift, which would look frozen in three seconds:
    /// over the clip's three seconds the blobs travel about as far as in half a minute in the app's preview.
    static let speed = 2.0

    /// Where the sky's white sits in the HDR movie, in nits. BT.2408's reference white is 203, but on the lock screen
    /// that glows brighter than the rest of the screen while it plays.
    static let white = 203.0

    /// The movie's size upright. 3:4 like the camera's, and the long side no more than 1920, which iOS requires.
    static let uprightSize = CGSize(width: 1440, height: 1920)

    /// Gets 0...1 as frames are drawn.
    typealias Progress = @Sendable (Double) -> Void

    enum Failure: Error {
        case notAllowed, rendering, writing, missingReference
    }

    /// The capture whose metadata the movie borrows, from `LivePhotoReference.json`.
    struct Reference: Decodable {
        /// Each frame's presentation time, in `timescale` units.
        var frames: [Int64]
        var timescale: Int32
        var duration: Int64
        /// When the still is taken, in `timescale` units.
        var still: Int64

        static func bundled() throws -> (reference: Self, movie: URL, photo: URL) {
            guard let json = Bundle.main.url(forResource: "LivePhotoReference", withExtension: "json"),
                  let movie = Bundle.main.url(forResource: "LivePhotoReference", withExtension: "mov"),
                  let photo = Bundle.main.url(forResource: "LivePhotoReference", withExtension: "heic")
            else { throw Failure.missingReference }
            return try (JSONDecoder().decode(Self.self, from: Data(contentsOf: json)), movie, photo)
        }

        func time(_ value: Int64) -> CMTime { CMTime(value: value, timescale: timescale) }
    }

    /// Renders the sky at `date` and saves it to Photos as a Live Photo.
    @concurrent static func save(at date: Date, spec: Wallpaper.Spec, white: Double = white, progress: Progress) async throws {
        guard await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized else { throw Failure.notAllowed }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let (photoURL, movieURL) = try await write(at: date, blockSize: spec.blockSize, white: white, into: folder, progress: progress)

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: photoURL, options: nil)
            request.addResource(with: .pairedVideo, fileURL: movieURL, options: nil)
        }
    }

    typealias Files = (photo: URL, movie: URL)

    /// Writes the Live Photo's two files into `folder`. The still shows the sky as a wallpaper rendered at `date` would.
    static func write(at date: Date, blockSize: Double, white: Double, into folder: URL, progress: Progress) async throws -> Files {
        let photo = folder.appendingPathComponent("Ditherglow.heic")
        let movie = folder.appendingPathComponent("Ditherglow.mov")
        let (reference, referenceMovie, referencePhoto) = try Reference.bundled()
        let identifier = UUID().uuidString
        let stillSeconds = reference.time(reference.still).seconds
        let writer = try await MovieWriter(url: movie, identifier: identifier, reference: reference, referenceMovie: referenceMovie)
        let still = try await writer.write(progress: progress) { seconds, context in
            let time = SkyImage.time(at: date) + (seconds - stillSeconds) * speed
            drawSideways(at: date, time: time, blockSize: blockSize, white: white, in: context)
        }
        try writePhoto(still, to: photo, identifier: identifier, referencePhoto: referencePhoto)
        return (photo, movie)
    }

    // MARK: - Movie

    /// Our frames on the reference's frame times, alongside the reference's own audio and metadata tracks.
    private final class MovieWriter {
        let writer: AVAssetWriter
        let reference: Reference
        let video: AVAssetWriterInput
        let pixels: AVAssetWriterInputPixelBufferAdaptor
        let reader: AVAssetReader
        /// The reference's audio and metadata tracks, copied sample for sample (its audio is already silenced).
        var copies: [(input: AVAssetWriterInput, output: AVAssetReaderTrackOutput)] = []
        /// Stored sideways, as the camera does.
        let width = Int(uprightSize.height), height = Int(uprightSize.width)

        init(url: URL, identifier: String, reference: Reference, referenceMovie: URL) async throws {
            self.reference = reference
            writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            video = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel],
                AVVideoColorPropertiesKey: [
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_2100_HLG,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020,
                ],
            ])
            video.expectsMediaDataInRealTime = false
            // Turns the sideways frames upright on playback, as in the camera's own files.
            video.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: CGFloat(height), ty: 0)
            pixels = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_64RGBALE,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ])
            writer.add(video)

            let asset = AVURLAsset(url: referenceMovie)
            reader = try AVAssetReader(asset: asset)
            for type in [AVMediaType.audio, .metadata] {
                for track in try await asset.loadTracks(withMediaType: type) {
                    try await addCopy(of: track, type: type)
                }
            }
            // The reference's top-level keys (vitality score, live-photo.auto and so on), plus our own identifier.
            writer.metadata = try await asset.loadMetadata(for: .quickTimeMetadata).filter {
                ($0.key as? String) != Self.identifierKey
            } + [Self.identifierItem(identifier)]
        }

        static let identifierKey = "com.apple.quicktime.content.identifier"

        static func identifierItem(_ identifier: String) -> AVMetadataItem {
            let item = AVMutableMetadataItem()
            item.keySpace = .quickTimeMetadata
            item.key = identifierKey as NSString
            item.value = identifier as NSString
            item.dataType = "com.apple.metadata.datatype.UTF-8"
            return item
        }

        private func addCopy(of track: AVAssetTrack, type: AVMediaType) async throws {
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            reader.add(output)
            let input = try await AVAssetWriterInput(mediaType: type, outputSettings: nil, sourceFormatHint: track.load(.formatDescriptions).first)
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else { throw Failure.writing }
            writer.add(input)
            copies.append((input, output))
        }

        /// Writes the movie, with `frame` drawing the frame at a given second into a sideways context,
        /// and returns the frame at the reference's still time.
        func write(progress: Progress, frame: (Double, CGContext) -> Void) async throws -> CGImage {
            guard writer.startWriting() else { throw writer.error ?? Failure.writing }
            guard reader.startReading() else { throw reader.error ?? Failure.writing }
            writer.startSession(atSourceTime: .zero)
            // One 16-bit HLG context to draw in, laid out as the pixel buffers are;
            // each frame is copied into a fresh buffer from the writer's pool.
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 16, bytesPerRow: width * 8,
                                          space: CGColorSpace(name: CGColorSpace.itur_2100_HLG)!,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)
            else { throw Failure.rendering }

            // Feed every track round-robin: the writer interleaves them, so it can stall one waiting on another.
            var finished = Array(repeating: false, count: copies.count)
            while nextFrame <= reference.frames.count || finished.contains(false) {
                var progressed = try feedVideo(context: context, progress: progress, frame: frame)
                for i in copies.indices where !finished[i] {
                    let (moved, done) = try feedCopy(i)
                    progressed = progressed || moved
                    finished[i] = done
                }
                if !progressed { try await Task.sleep(for: .milliseconds(2)) }
            }

            writer.endSession(atSourceTime: reference.time(reference.duration))
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? Failure.writing }
            guard let still else { throw Failure.rendering }
            return still
        }

        /// The next frame to write; one past the last once the video track is finished.
        private var nextFrame = 0
        private var still: CGImage?

        /// Draws and appends frames while the video input takes them; returns whether any went in.
        private func feedVideo(context: CGContext, progress: Progress, frame: (Double, CGContext) -> Void) throws -> Bool {
            var moved = false
            while nextFrame <= reference.frames.count, video.isReadyForMoreMediaData {
                defer { nextFrame += 1 }
                guard nextFrame < reference.frames.count else {
                    video.markAsFinished()
                    break
                }
                let presentation = reference.time(reference.frames[nextFrame])
                frame(presentation.seconds, context)
                if reference.frames[nextFrame] == reference.still { still = context.makeImage() }
                try append(context, at: presentation)
                progress(Double(nextFrame + 1) / Double(reference.frames.count))
                moved = true
            }
            return moved
        }

        /// Copies what the reference track's input will take; returns whether anything moved and whether the track is done.
        private func feedCopy(_ i: Int) throws -> (moved: Bool, done: Bool) {
            let (input, output) = copies[i]
            var moved = false
            while input.isReadyForMoreMediaData {
                guard let sample = output.copyNextSampleBuffer() else {
                    input.markAsFinished()
                    return (moved, true)
                }
                guard input.append(sample) else { throw writer.error ?? Failure.writing }
                moved = true
            }
            return (moved, false)
        }

        private func append(_ context: CGContext, at time: CMTime) throws {
            guard let pool = pixels.pixelBufferPool else { throw Failure.writing }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer, let source = context.data else { throw Failure.rendering }
            CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_2020, .shouldPropagate)
            CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_2100_HLG, .shouldPropagate)
            CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_2020, .shouldPropagate)
            CVPixelBufferLockBaseAddress(buffer, [])
            defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
            guard let destination = CVPixelBufferGetBaseAddress(buffer) else { throw Failure.rendering }
            let rowBytes = context.bytesPerRow, bufferRowBytes = CVPixelBufferGetBytesPerRow(buffer)
            for row in 0..<context.height {
                memcpy(destination + row * bufferRowBytes, source + row * rowBytes, min(rowBytes, bufferRowBytes))
            }
            guard pixels.append(buffer, withPresentationTime: time) else { throw Failure.writing }
        }
    }

    /// Draws the sky upright, then rotated 90° counter-clockwise into the sideways `context`.
    /// The sky goes into HLG with its white at `white` nits.
    private static func drawSideways(at date: Date, time: Double, blockSize: Double, white: Double, in context: CGContext) {
        guard let sky = CGContext(data: nil, width: Int(uprightSize.width), height: Int(uprightSize.height), bitsPerComponent: 16,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.itur_2100_HLG)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)
        else { return }
        // Dither blocks sized as on a phone screen of the same width, at about 3 pixels per point.
        let points = CGSize(width: uprightSize.width / 3, height: uprightSize.height / 3)
        SkyImage.draw(at: date, time: time, size: points, blockSize: blockSize, encoding: .hlg(white: white), in: sky)
        guard let image = sky.makeImage() else { return }
        context.saveGState()
        // The upright top edge lands on the stored image's left edge.
        context.translateBy(x: CGFloat(context.width), y: 0)
        context.rotate(by: .pi / 2)
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(origin: .zero, size: uprightSize))
        context.restoreGState()
    }
}

// MARK: - Photo

nonisolated extension LivePhoto {
    /// The reference photo's own size and format, which the still replaces, and its location.
    private static var droppedPhotoKeys: [CFString] { [
        kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight, kCGImagePropertyDepth, kCGImagePropertyColorModel,
        kCGImagePropertyProfileName, kCGImagePropertyHasAlpha, kCGImagePropertyGPSDictionary,
    ] }

    /// The still, as HEIC stored sideways and tagged to rotate 90° clockwise, with the reference's photo metadata
    /// and the movie's content identifier in Apple's maker note (tag 17).
    private static func writePhoto(_ image: CGImage, to url: URL, identifier: String, referencePhoto: URL) throws {
        guard let source = CGImageSourceCreateWithURL(referencePhoto as CFURL, nil),
              var properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil)
        else { throw Failure.writing }
        for key in droppedPhotoKeys {
            properties.removeValue(forKey: key)
        }
        properties = restamped(properties, at: Date())

        var maker = properties[kCGImagePropertyMakerAppleDictionary] as? [String: Any] ?? [:]
        maker["17"] = identifier
        properties[kCGImagePropertyMakerAppleDictionary] = maker
        var exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        exif[kCGImagePropertyExifPixelXDimension] = image.width
        exif[kCGImagePropertyExifPixelYDimension] = image.height
        exif.removeValue(forKey: kCGImagePropertyExifSubjectArea)
        properties[kCGImagePropertyExifDictionary] = exif
        let right = CGImagePropertyOrientation.right.rawValue
        properties[kCGImagePropertyOrientation] = right
        var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        tiff[kCGImagePropertyTIFFOrientation] = right
        properties[kCGImagePropertyTIFFDictionary] = tiff
        properties[kCGImageDestinationLossyCompressionQuality] = 0.95
        // An SDR base image plus a gain map toward the HLG still, as the camera writes HDR photos.
        if #available(iOS 18, *) {
            properties[kCGImageDestinationEncodeRequest] = kCGImageDestinationEncodeToISOGainmap
        }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.writing }
    }

    /// Gives the photo metadata its own capture time and identifiers. Apple maker-note tags 11 and 43 are per-capture UUIDs.
    private static func restamped(_ properties: [CFString: Any], at date: Date) -> [CFString: Any] {
        var properties = properties
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy:MM:dd HH:mm:ss"
        let offset = DateFormatter()
        offset.locale = stamp.locale
        offset.dateFormat = "xxx"
        let subsecond = String(format: "%03d", Int(date.timeIntervalSince1970 * 1000) % 1000)
        if var maker = properties[kCGImagePropertyMakerAppleDictionary] as? [String: Any] {
            for tag in ["11", "43"] where maker[tag] != nil {
                maker[tag] = UUID().uuidString
            }
            properties[kCGImagePropertyMakerAppleDictionary] = maker
        }
        var exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        exif[kCGImagePropertyExifDateTimeOriginal] = stamp.string(from: date)
        exif[kCGImagePropertyExifDateTimeDigitized] = stamp.string(from: date)
        for key in [kCGImagePropertyExifOffsetTime, kCGImagePropertyExifOffsetTimeOriginal, kCGImagePropertyExifOffsetTimeDigitized] {
            exif[key] = offset.string(from: date)
        }
        exif[kCGImagePropertyExifSubsecTimeOriginal] = subsecond
        exif[kCGImagePropertyExifSubsecTimeDigitized] = subsecond
        properties[kCGImagePropertyExifDictionary] = exif
        var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        tiff[kCGImagePropertyTIFFDateTime] = stamp.string(from: date)
        properties[kCGImagePropertyTIFFDictionary] = tiff
        return properties
    }
}
