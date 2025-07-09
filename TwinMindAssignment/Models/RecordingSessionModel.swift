//
//  RecordingSessionModel.swift
//  TwinMindAssignment
//
//  Created by Noor Bhatia on 08/07/25.
//

import Foundation
import SwiftData
import UIKit

/// Represents a complete recording session with metadata and segments
@Model
final class RecordingSession {
    
    // MARK: - Core Properties
    var id: UUID
    var title: String
    var startTime: Date
    var endTime: Date?
    var duration: TimeInterval
    var fileURL: URL?
    var fileSize: Int64
    
    // MARK: - Audio Configuration
    var sampleRate: Double
    var bitDepth: Int
    var channels: Int
    var audioFormat: String
    var audioQuality: String
    
    // MARK: - Session State
    var isCompleted: Bool
    var wasInterrupted: Bool
    var backgroundRecordingUsed: Bool
    
    // MARK: - Metadata
    var createdAt: Date
    var updatedAt: Date
    var deviceModel: String
    var osVersion: String
    var appVersion: String
    
    // MARK: - Relationships
    @Relationship(deleteRule: .cascade, inverse: \AudioSegment.session)
    var segments: [AudioSegment] = []
    
    // MARK: - Computed Properties
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    var completedTranscriptionsCount: Int {
        segments.filter { $0.transcription?.isCompleted == true }.count
    }
    
    var totalTranscriptionsCount: Int {
        segments.count
    }
    
    var transcriptionProgress: Double {
        guard totalTranscriptionsCount > 0 else { return 0.0 }
        return Double(completedTranscriptionsCount) / Double(totalTranscriptionsCount)
    }
    
    var fullTranscriptionText: String {
        segments
            .compactMap { $0.transcription?.text }
            .joined(separator: " ")
    }
    
    // MARK: - Initialization
    init(
        title: String? = nil,
        startTime: Date = Date(),
        sampleRate: Double,
        bitDepth: Int,
        channels: Int,
        audioFormat: String,
        audioQuality: String,
        deviceModel: String = UIDevice.current.model,
        osVersion: String = UIDevice.current.systemVersion,
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    ) {
        self.id = UUID()
        self.title = title ?? "Recording \(DateFormatter.sessionFormatter.string(from: startTime))"
        self.startTime = startTime
        self.endTime = nil
        self.duration = 0
        self.fileURL = nil
        self.fileSize = 0
        
        // Audio configuration
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.channels = channels
        self.audioFormat = audioFormat
        self.audioQuality = audioQuality
        
        // Session state
        self.isCompleted = false
        self.wasInterrupted = false
        self.backgroundRecordingUsed = false
        
        // Metadata
        self.createdAt = startTime
        self.updatedAt = startTime
        self.deviceModel = deviceModel
        self.osVersion = osVersion
        self.appVersion = appVersion
    }
    
    // MARK: - Session Management
    
    /// Completes the recording session
    func complete(endTime: Date, fileURL: URL, fileSize: Int64, wasInterrupted: Bool = false, backgroundRecordingUsed: Bool = false) {
        self.endTime = endTime
        self.duration = endTime.timeIntervalSince(startTime)
        self.fileURL = fileURL
        self.fileSize = fileSize
        self.isCompleted = true
        self.wasInterrupted = wasInterrupted
        self.backgroundRecordingUsed = backgroundRecordingUsed
        self.updatedAt = Date()
    }
    
    /// Updates the session title
    func updateTitle(_ newTitle: String) {
        self.title = newTitle
        self.updatedAt = Date()
    }
    
    /// Marks session as interrupted
    func markAsInterrupted() {
        self.wasInterrupted = true
        self.updatedAt = Date()
    }
}
// MARK: - Query Helpers

extension RecordingSession {
    
    /// Predicate for completed sessions
    static var completedSessionsPredicate: Predicate<RecordingSession> {
        #Predicate<RecordingSession> { session in
            session.isCompleted == true
        }
    }
    
    /// Predicate for sessions from today
    static var todaySessionsPredicate: Predicate<RecordingSession> {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        
        return #Predicate<RecordingSession> { session in
            session.createdAt >= startOfDay && session.createdAt < endOfDay
        }
    }
    
    /// Predicate for sessions with incomplete transcriptions
    static var incompleteTranscriptionsPredicate: Predicate<RecordingSession> {
        #Predicate<RecordingSession> { session in
            session.isCompleted == true &&
            session.segments.contains { segment in
                segment.transcription?.isCompleted != true
            }
        }
    }
}
