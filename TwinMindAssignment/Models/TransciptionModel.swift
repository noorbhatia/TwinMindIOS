//
//  TransciptionModel.swift
//  TwinMindAssignment
//
//  Created by Noor Bhatia on 08/07/25.
//

import Foundation
import SwiftData
import UIKit

/// Represents transcription data and metadata
@Model
final class Transcription {
    
    // MARK: - Core Properties
    var id: UUID
    var text: String
    var language: String?
    
    // MARK: - Processing Details
    var processingMethod: TranscriptionMethod
    var apiProvider: String?
    var modelUsed: String?
    var processingDuration: TimeInterval
    var isCompleted: Bool
    
    // MARK: - Quality Metrics
    var wordCount: Int
    var characterCount: Int
    var estimatedAccuracy: Double?
    
    // MARK: - Metadata
    var createdAt: Date
    var updatedAt: Date
    var processedAt: Date?
    
    // MARK: - Relationships
    @Relationship var audioSegment: AudioSegment?
    
    // MARK: - Enums
    enum TranscriptionMethod: String, CaseIterable, Codable {
        case openaiWhisper = "openai_whisper"
        case appleOnDevice = "apple_ondevice"
        case appleSpeechRecognition = "apple_speech_recognition"
        case localWhisper = "local_whisper"
        case unknown = "unknown"
        
        var displayName: String {
            switch self {
            case .openaiWhisper: return "OpenAI Whisper"
            case .appleOnDevice: return "Apple On-Device"
            case .appleSpeechRecognition: return "Apple Speech Recognition"
            case .localWhisper: return "Local Whisper"
            case .unknown: return "Unknown"
            }
        }
        
        var isNetworkBased: Bool {
            switch self {
            case .openaiWhisper: return true
            case .appleOnDevice, .appleSpeechRecognition, .localWhisper: return false
            case .unknown: return false
            }
        }
    }
    
    var wordsPerMinute: Double? {
        guard let segment = audioSegment, segment.duration > 0, wordCount > 0 else { return nil }
        return Double(wordCount) / (segment.duration / 60.0)
    }
    
    // MARK: - Initialization
    init(
        text: String,
        confidence: Double = 0.0,
        language: String? = nil,
        processingMethod: TranscriptionMethod,
        apiProvider: String? = nil,
        modelUsed: String? = nil,
        processingDuration: TimeInterval = 0,
        audioSegment: AudioSegment? = nil
    ) {
        self.id = UUID()
        self.text = text
        self.language = language
        
        // Processing details
        self.processingMethod = processingMethod
        self.apiProvider = apiProvider
        self.modelUsed = modelUsed
        self.processingDuration = processingDuration
        self.isCompleted = false
        
        // Quality metrics
        self.wordCount = text.split(separator: " ").count
        self.characterCount = text.count
        self.estimatedAccuracy = nil
        
        // Metadata
        self.createdAt = Date()
        self.updatedAt = Date()
        self.processedAt = nil
        
        // Relationships
        self.audioSegment = audioSegment
    }
    
    // MARK: - Transcription Management
    
    /// Marks transcription as completed
    func complete(confidence: Double? = nil, language: String? = nil, estimatedAccuracy: Double? = nil) {
        self.isCompleted = true
        self.processedAt = Date()
        self.updatedAt = Date()
        
        if let language = language {
            self.language = language
        }
        if let accuracy = estimatedAccuracy {
            self.estimatedAccuracy = accuracy
        }
    }
    
    /// Updates the transcription text and recalculates metrics
    func updateText(_ newText: String) {
        self.text = newText
        self.wordCount = newText.split(separator: " ").count
        self.characterCount = newText.count
        self.updatedAt = Date()
    }
}
// MARK: - Extensions

extension DateFormatter {
    static let sessionFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return formatter
    }()
    
    static let segmentFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
