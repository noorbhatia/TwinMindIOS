//
//  SegmentModel.swift
//  TwinMindAssignment
//
//  Created by Noor Bhatia on 08/07/25.
//

import Foundation
import SwiftData
import UIKit
/// Represents a segment of audio for transcription (typically 30 seconds)
@Model
final class AudioSegment {
    
    // MARK: - Core Properties
    var id: UUID
    var segmentIndex: Int
    var startTime: TimeInterval
    var endTime: TimeInterval
    var duration: TimeInterval
    var fileURL: URL?
    var fileSize: Int64
    
    // MARK: - Processing State
    var isProcessed: Bool
    var processingStartTime: Date?
    var processingEndTime: Date?
    var failureCount: Int
    var lastFailureReason: String?
    
    // MARK: - Metadata
    var createdAt: Date
    var updatedAt: Date
    
    // MARK: - Relationships
    @Relationship var session: RecordingSession?
    @Relationship(deleteRule: .cascade)
    var transcription: Transcription?
    
    // MARK: - Computed Properties
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var processingDuration: TimeInterval? {
        guard let start = processingStartTime,
              let end = processingEndTime else { return nil }
        return end.timeIntervalSince(start)
    }
    
    var shouldRetryTranscription: Bool {
        !isProcessed && failureCount < 5
    }
    
    // MARK: - Initialization
    init(
        segmentIndex: Int,
        startTime: TimeInterval,
        endTime: TimeInterval,
        session: RecordingSession? = nil
    ) {
        self.id = UUID()
        self.segmentIndex = segmentIndex
        self.startTime = startTime
        self.endTime = endTime
        self.duration = endTime - startTime
        self.fileURL = nil
        self.fileSize = 0
        
        // Processing state
        self.isProcessed = false
        self.processingStartTime = nil
        self.processingEndTime = nil
        self.failureCount = 0
        self.lastFailureReason = nil
        
        // Metadata
        self.createdAt = Date()
        self.updatedAt = Date()
        
        // Relationships
        self.session = session
    }
    
    // MARK: - Processing Management
    
    /// Starts processing this segment
    func startProcessing() {
        processingStartTime = Date()
        updatedAt = Date()
    }
    
    /// Marks processing as completed successfully
    func completeProcessing() {
        processingEndTime = Date()
        isProcessed = true
        updatedAt = Date()
    }
    
    /// Records a processing failure
    func recordFailure(reason: String) {
        failureCount += 1
        lastFailureReason = reason
        processingEndTime = Date()
        updatedAt = Date()
    }
    
    /// Updates the file information for this segment
    func updateFile(url: URL, size: Int64) {
        self.fileURL = url
        self.fileSize = size
        self.updatedAt = Date()
    }
}
extension AudioSegment {
    
    /// Predicate for unprocessed segments
    static var unprocessedSegmentsPredicate: Predicate<AudioSegment> {
        #Predicate<AudioSegment> { segment in
            segment.isProcessed == false && segment.failureCount < 5
        }
    }
    
    /// Predicate for failed segments that can be retried
    static var retryableSegmentsPredicate: Predicate<AudioSegment> {
        #Predicate<AudioSegment> { segment in
            segment.isProcessed == false &&
            segment.failureCount > 0 &&
            segment.failureCount < 5
        }
    }
} 
