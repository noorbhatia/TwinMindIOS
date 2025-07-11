import Foundation
import AVFoundation
import SwiftData

/// Service responsible for segmenting audio recordings into smaller chunks for transcription
@MainActor
final class AudioSegmentationService: ObservableObject {
    
    // MARK: - Published Properties
    @Published var isSegmenting = false
    @Published var segmentationProgress: Double = 0.0
    @Published var currentSegmentIndex = 0
    @Published var totalSegments = 0
    
    // MARK: - Configuration
    struct SegmentationConfig {
        let segmentDuration: TimeInterval
        let overlapDuration: TimeInterval
        let minimumSegmentDuration: TimeInterval
        let audioFormat: AVAudioFormat
        
        static let defaultConfig = SegmentationConfig(
            segmentDuration: 30.0,        // 30 seconds per segment
            overlapDuration: 0.5,         // 0.5 second overlap for context
            minimumSegmentDuration: 5.0,  // Minimum 5 seconds for last segment
            audioFormat: AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        )
        
        static let highQualityConfig = SegmentationConfig(
            segmentDuration: 30.0,
            overlapDuration: 1.0,
            minimumSegmentDuration: 10.0,
            audioFormat: AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        )
    }
    
    // MARK: - Private Properties
    private let modelContext: ModelContext
    private let fileManager = FileManager.default
    private var segmentationTask: Task<Void, Error>?
    private let errorManager: ErrorManager?
    
    // File paths
    private lazy var segmentsDirectory: URL = {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let segmentsPath = documentsPath.appendingPathComponent("AudioSegments")
        
        // Create directory if it doesn't exist
        try? fileManager.createDirectory(at: segmentsPath, withIntermediateDirectories: true)
        
        return segmentsPath
    }()
    
    // MARK: - Initialization
    init(modelContext: ModelContext, errorManager: ErrorManager? = nil) {
        self.modelContext = modelContext
        self.errorManager = errorManager
    }
    
    deinit {
        segmentationTask?.cancel()
    }
    
    // MARK: - Public Methods
    
    /// Segments a recording session into smaller chunks for transcription
    func segmentRecording(
        session: Session,
        config: SegmentationConfig = .defaultConfig
    ) async throws {
        
        guard let fileURL = session.fileURL else {
            reportError(.storage(.fileNotFound), operation: "segmentRecording")
            throw NSError(domain: "SegmentationError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid source file"])
        }
        
        guard !isSegmenting else {
            reportError(.system(.cpuThrottling), operation: "segmentRecording")
            throw NSError(domain: "SegmentationError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Segmentation already in progress"])
        }
        
        // Validate source file exists
        guard fileManager.fileExists(atPath: fileURL.path) else {
            reportError(.storage(.fileNotFound), operation: "segmentRecording")
            throw NSError(domain: "SegmentationError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Source file not found"])
        }
        
        isSegmenting = true
        segmentationProgress = 0.0
        currentSegmentIndex = 0
        
        defer {
            isSegmenting = false
            segmentationProgress = 0.0
            currentSegmentIndex = 0
            totalSegments = 0
        }
        
        do {
            // Load the audio file
            let audioFile = try AVAudioFile(forReading: fileURL)
            let totalDuration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            
            // Calculate segment parameters
            let segments = calculateSegments(
                totalDuration: totalDuration,
                config: config
            )
            
            totalSegments = segments.count
            
            // Create and save audio segments
            for (index, segmentInfo) in segments.enumerated() {
                currentSegmentIndex = index + 1
                
                // Check for cancellation
                try Task.checkCancellation()
                
                // Create segment file
                let segmentURL = try await createSegmentFile(
                    sourceFile: audioFile,
                    segmentInfo: segmentInfo,
                    segmentIndex: index,
                    sessionId: session.id,
                    config: config
                )
                
                // Create AudioSegment model
                let audioSegment = AudioSegment(
                    segmentIndex: index,
                    startTime: segmentInfo.startTime,
                    endTime: segmentInfo.endTime,
                    session: session
                )
                
                // Get file size
                let fileSize = try getFileSize(url: segmentURL)
                audioSegment.updateFile(url: segmentURL, size: fileSize)
                
                // Add segment to session
                session.segments.append(audioSegment)
                
                // Insert segment into model context
                modelContext.insert(audioSegment)
                
                // Update progress
                segmentationProgress = Double(index + 1) / Double(totalSegments)
            }
            
            // Save the model context
            try modelContext.save()
            
        } catch {
            // Clean up any partial segments on error
            await cleanupPartialSegments(sessionId: session.id)
            reportError(.storage(.diskWriteError), operation: "segmentRecording")
            throw error
        }
    }
    
    /// Cancels the current segmentation operation
    func cancelSegmentation() {
        segmentationTask?.cancel()
    }
    
    /// Cleans up segment files for a specific session
    func cleanupSegments(for session: Session) async {
        await cleanupPartialSegments(sessionId: session.id)
        
        // Remove segments from model context
        for segment in session.segments {
            modelContext.delete(segment)
        }
        
        do {
            try modelContext.save()
        } catch {
            reportError(.data(.saveOperationFailed), operation: "cleanupSegments")
        }
    }
    
    /// Gets the total size of all segment files for a session
    func getSegmentsTotalSize(for session: Session) -> Int64 {
        return session.segments.reduce(0) { total, segment in
            total + segment.fileSize
        }
    }
    
    // MARK: - Private Methods
    
    private func reportError(_ error: ErrorManager.AppError, operation: String) {
        guard let errorManager = errorManager else { return }
        
        let context = ErrorManager.ErrorContext(
            component: "AudioSegmentationService",
            operation: operation,
            userAction: "User attempted audio segmentation"
        )
        errorManager.reportError(error, context: context)
    }
    
    private func calculateSegments(
        totalDuration: TimeInterval,
        config: SegmentationConfig
    ) -> [SegmentInfo] {
        
        var segments: [SegmentInfo] = []
        var currentTime: TimeInterval = 0
        
        while currentTime < totalDuration {
            let remainingDuration = totalDuration - currentTime
            
            // Determine segment end time
            let segmentEndTime: TimeInterval
            if remainingDuration <= config.segmentDuration + config.minimumSegmentDuration {
                // Include remaining audio in this segment if it's close to a full segment
                segmentEndTime = totalDuration
            } else {
                segmentEndTime = currentTime + config.segmentDuration
            }
            
            let segment = SegmentInfo(
                startTime: currentTime,
                endTime: segmentEndTime
            )
            segments.append(segment)
            
            // Move to next segment (subtract overlap for continuity)
            if segmentEndTime < totalDuration {
                currentTime = segmentEndTime - config.overlapDuration
            } else {
                break
            }
        }
        
        return segments
    }
    
    private func createSegmentFile(
        sourceFile: AVAudioFile,
        segmentInfo: SegmentInfo,
        segmentIndex: Int,
        sessionId: UUID,
        config: SegmentationConfig
    ) async throws -> URL {
        
        // Calculate frame positions
        let sampleRate = sourceFile.fileFormat.sampleRate
        let startFrame = AVAudioFramePosition(segmentInfo.startTime * sampleRate)
        let endFrame = AVAudioFramePosition(segmentInfo.endTime * sampleRate)
        let frameCount = AVAudioFrameCount(endFrame - startFrame)
        
        // Create output file URL
        let outputURL = segmentsDirectory.appendingPathComponent(
            "segment_\(sessionId.uuidString)_\(segmentIndex).wav"
        )
        
        // Create output audio file
        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: config.audioFormat.settings
        )
        
        // Read and write audio data in chunks to manage memory
        let bufferSize: AVAudioFrameCount = 4096
        var remainingFrames = frameCount
        var currentFrame = startFrame
        
        sourceFile.framePosition = startFrame
        
        while remainingFrames > 0 {
            let framesToRead = min(remainingFrames, bufferSize)
            
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: sourceFile.processingFormat,
                frameCapacity: framesToRead
            ) else {
                reportError(.storage(.fileCorrupted), operation: "createSegmentFile")
                throw NSError(domain: "SegmentationError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Buffer creation failed"])
            }
            
            // Read from source
            try sourceFile.read(into: buffer, frameCount: framesToRead)
            
            // Convert format if necessary
            if sourceFile.processingFormat != config.audioFormat {
                guard let convertedBuffer = await convertBuffer(
                    buffer,
                    to: config.audioFormat
                ) else {
                    reportError(.storage(.fileCorrupted), operation: "createSegmentFile")
                    throw NSError(domain: "SegmentationError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Format conversion failed"])
                }
                
                try outputFile.write(from: convertedBuffer)
            } else {
                try outputFile.write(from: buffer)
            }
            
            remainingFrames -= framesToRead
            currentFrame += AVAudioFramePosition(framesToRead)
            
            // Check for cancellation
            try Task.checkCancellation()
        }
        
        return outputURL
    }
    
    private func convertBuffer(
        _ inputBuffer: AVAudioPCMBuffer,
        to format: AVAudioFormat
    ) async -> AVAudioPCMBuffer? {
        
        guard let converter = AVAudioConverter(
            from: inputBuffer.format,
            to: format
        ) else {
            return nil
        }
        
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: inputBuffer.frameLength
        ) else {
            return nil
        }
        
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }
        
        guard status != .error else {
            return nil
        }
        
        return outputBuffer
    }
    
    private func getFileSize(url: URL) throws -> Int64 {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }
    
    private func cleanupPartialSegments(sessionId: UUID) async {
        let sessionPattern = "segment_\(sessionId.uuidString)_"
        
        do {
            let files = try fileManager.contentsOfDirectory(at: segmentsDirectory, includingPropertiesForKeys: nil)
            
            for file in files {
                if file.lastPathComponent.hasPrefix(sessionPattern) {
                    try? fileManager.removeItem(at: file)
                }
            }
        } catch {
            print("Failed to cleanup partial segments: \(error)")
            reportError(.storage(.fileCleanupFailed), operation: "cleanupPartialSegments")
        }
    }
}

// MARK: - Supporting Types

struct SegmentInfo {
    let startTime: TimeInterval
    let endTime: TimeInterval
    
    var duration: TimeInterval {
        endTime - startTime
    }
}

// MARK: - Extensions

extension AudioSegmentationService {
    
    /// Estimates the total number of segments for a given duration
    func estimateSegmentCount(
        for duration: TimeInterval,
        config: SegmentationConfig = .defaultConfig
    ) -> Int {
        let segments = calculateSegments(totalDuration: duration, config: config)
        return segments.count
    }
    
    /// Estimates the total storage size for segmented audio
    func estimateStorageSize(
        for duration: TimeInterval,
        originalFileSize: Int64,
        config: SegmentationConfig = .defaultConfig
    ) -> Int64 {
        // Rough estimation: segments will be approximately the same size as original
        // with some overhead for file headers
        let segmentCount = estimateSegmentCount(for: duration, config: config)
        let avgSegmentSize = originalFileSize / Int64(max(1, Int(duration / config.segmentDuration)))
        let headerOverhead: Int64 = 1024 * Int64(segmentCount) // ~1KB overhead per file
        
        return (avgSegmentSize * Int64(segmentCount)) + headerOverhead
    }
    
    /// Validates available storage space before segmentation
    func validateStorageSpace(
        for session: Session,
        config: SegmentationConfig = .defaultConfig
    ) throws {
        guard let sourceURL = session.fileURL else {
            reportError(.storage(.fileNotFound), operation: "validateStorageSpace")
            throw NSError(domain: "SegmentationError", code: 6, userInfo: [NSLocalizedDescriptionKey: "Invalid source file"])
        }
        
        // Get available space
        guard let attributes = try? fileManager.attributesOfFileSystem(forPath: segmentsDirectory.path),
              let freeSpace = attributes[.systemFreeSize] as? NSNumber else {
            reportError(.storage(.insufficientSpace), operation: "validateStorageSpace")
            throw NSError(domain: "SegmentationError", code: 7, userInfo: [NSLocalizedDescriptionKey: "Insufficient storage space"])
        }
        
        // Estimate required space (with 50% buffer)
        let estimatedSize = estimateStorageSize(
            for: session.duration,
            originalFileSize: session.fileSize,
            config: config
        )
        let requiredSpace = estimatedSize + (estimatedSize / 2)
        
        if freeSpace.int64Value < requiredSpace {
            reportError(.storage(.insufficientSpace), operation: "validateStorageSpace")
            throw NSError(domain: "SegmentationError", code: 8, userInfo: [NSLocalizedDescriptionKey: "Insufficient storage space"])
        }
    }
} 
