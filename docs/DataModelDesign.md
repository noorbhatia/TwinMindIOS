# Data Model Design

## Overview

TwinMindAssignment uses SwiftData as the primary persistence framework, designed to efficiently handle large datasets with complex relationships. The data model is optimized for performance with thousands of recording sessions and tens of thousands of audio segments while maintaining data integrity and supporting advanced querying capabilities.

## SwiftData Schema Architecture

### Core Data Models

The application uses a hierarchical data model with three primary entities:

```
Session (1) ──── (N) AudioSegment (1) ──── (1) Transcription
     │                        │
     │                        │
     └── Metadata             └── Audio Data
     └── User Settings        └── Processing Status
```

### Model Definitions

#### 1. Session
**Primary Entity for Recording Sessions**

```swift
@Model
final class Session {
    // Core Properties
    var id: UUID
    var title: String
    var startTime: Date
    var endTime: Date?
    var duration: TimeInterval
    var fileURL: URL?
    var fileSize: Int64
    
    // Audio Configuration
    var sampleRate: Double
    var bitDepth: Int
    var channels: Int
    var audioFormat: String
    var audioQuality: String
    
    // Session State
    var isCompleted: Bool
    var wasInterrupted: Bool
    var backgroundRecordingUsed: Bool
    
    // Metadata
    var createdAt: Date
    var updatedAt: Date
    var deviceModel: String
    var osVersion: String
    var appVersion: String
    
    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \AudioSegment.session)
    var segments: [AudioSegment] = []
    
    // Computed Properties
    var formattedDuration: String { /* implementation */ }
    var formattedFileSize: String { /* implementation */ }
    var completedTranscriptionsCount: Int { /* implementation */ }
    var totalTranscriptionsCount: Int { /* implementation */ }
    var transcriptionProgress: Double { /* implementation */ }
    var isTranscriptionCompleted: Bool { /* implementation */ }
    var isTranscriptionFailed: Bool { /* implementation */ }
    var fullTranscriptionText: String { /* implementation */ }
}
```

#### 2. AudioSegment
**Audio Segment Entity**

```swift
@Model
final class AudioSegment {
    // Core Properties
    var id: UUID
    var segmentIndex: Int
    var startTime: TimeInterval
    var endTime: TimeInterval
    var duration: TimeInterval
    var fileURL: URL?
    var fileSize: Int64
    
    // Processing State
    var isProcessed: Bool
    var processingStartTime: Date?
    var processingEndTime: Date?
    var failureCount: Int
    var lastFailureReason: String?
    
    // Metadata
    var createdAt: Date
    var updatedAt: Date
    
    // Relationships
    @Relationship var session: Session?
    @Relationship(deleteRule: .cascade) var transcription: Transcription?
    
    // Computed Properties
    var formattedDuration: String { /* implementation */ }
    var processingDuration: TimeInterval? { /* implementation */ }
    var shouldRetryTranscription: Bool { /* implementation */ }
    
    // Processing Management Methods
    func startProcessing()
    func completeProcessing()
    func recordFailure(reason: String)
    func updateFile(url: URL, size: Int64)
}
```

#### 3. Transcription
**Transcription Data Entity**

```swift
@Model
final class Transcription {
    // Core Properties
    var id: UUID
    var text: String
    var language: String?
    
    // Processing Details
    var processingMethod: TranscriptionMethod
    var apiProvider: String?
    var modelUsed: String?
    var processingDuration: TimeInterval
    var isCompleted: Bool
    
    // Quality Metrics
    var wordCount: Int
    var characterCount: Int
    var estimatedAccuracy: Double?
    
    // Metadata
    var createdAt: Date
    var updatedAt: Date
    var processedAt: Date?
    
    // Relationships
    @Relationship var audioSegment: AudioSegment?
    
    // Computed Properties
    var wordsPerMinute: Double? { /* implementation */ }
    
    // Management Methods
    func complete(confidence: Double?, language: String?, estimatedAccuracy: Double?)
    func updateText(_ newText: String)
    
    // Enum for transcription methods
    enum TranscriptionMethod: String, CaseIterable, Codable {
        case openaiWhisper = "openai_whisper"
        case appleOnDevice = "apple_ondevice"
        case appleSpeechRecognition = "apple_speech_recognition"
        case localWhisper = "local_whisper"
        case unknown = "unknown"
    }
}
```

### Supporting Enums and Types

```swift
// Audio Configuration Structure
struct AudioConfiguration {
    let sampleRate: Double
    let bitDepth: UInt32
    let channels: UInt32
    let fileFormat: AudioFileFormat
    
    static let high = AudioConfiguration(
        sampleRate: 44100.0,
        bitDepth: 16,
        channels: 1,
        fileFormat: .wav
    )
    
    static let medium = AudioConfiguration(
        sampleRate: 22050.0,
        bitDepth: 16,
        channels: 1,
        fileFormat: .wav
    )
    
    static let low = AudioConfiguration(
        sampleRate: 16000.0,
        bitDepth: 16,
        channels: 1,
        fileFormat: .wav
    )
}

// File Format Enum
enum AudioFileFormat: String, CaseIterable, Codable {
    case wav = "wav"
    case m4a = "m4a"
    case aac = "aac"
}

// Recording State Enum
enum RecordingState {
    case stopped
    case recording
    case paused
    case error(String)
}

// Transcription Method (from Transcription model)
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
```

## Performance Optimizations

### 1. Indexing Strategy

**Primary Indexes:**
```swift
// Automatic indexes on @Attribute(.unique) properties
// SessionModel.id, SegmentModel.id, TranscriptionModel.id

// Custom indexes for frequently queried fields
@Model
final class SessionModel {
    @Attribute(.unique) var id: UUID
    
    // Index for date-based queries
    @Index([\.createdAt])
    var createdAt: Date
    
    // Index for completion status filtering
    @Index([\.isCompleted])
    var isCompleted: Bool
    
    // Compound index for efficient session listing
    @Index([\.createdAt, \.isCompleted])
    var sessionListingIndex: (Date, Bool) {
        (createdAt, isCompleted)
    }
}

@Model
final class SegmentModel {
    @Attribute(.unique) var id: UUID
    
    // Index for sequence-based queries
    @Index([\.sequenceNumber])
    var sequenceNumber: Int
    
    // Index for transcription status filtering
    @Index([\.transcriptionStatus])
    var transcriptionStatus: TranscriptionStatus
    
    // Compound index for session segments
    @Index([\.session, \.sequenceNumber])
    var sessionSegmentIndex: (SessionModel?, Int) {
        (session, sequenceNumber)
    }
}
```

### 2. Batch Operations

**Efficient Batch Processing:**
```swift
class DataManager {
    private let modelContext: ModelContext
    
    func batchUpdateTranscriptions(_ updates: [(SegmentModel, String, Double)]) throws {
        // Batch update for better performance
        for (segment, text, confidence) in updates {
            if let existingTranscription = segment.transcription {
                existingTranscription.text = text
                existingTranscription.confidence = confidence
                existingTranscription.lastUpdated = Date()
            } else {
                let transcription = TranscriptionModel(
                    text: text,
                    confidence: confidence,
                    service: .openaiWhisper
                )
                segment.transcription = transcription
            }
            segment.isTranscribed = true
            segment.transcriptionStatus = .completed
        }
        
        try modelContext.save()
    }
    
    func batchDeleteSessions(_ sessions: [SessionModel]) throws {
        for session in sessions {
            modelContext.delete(session)
        }
        try modelContext.save()
    }
}
```

### 3. Lazy Loading and Pagination

**Efficient Data Loading:**
```swift
class SessionListViewModel: ObservableObject {
    @Published var sessions: [SessionModel] = []
    @Published var isLoading = false
    
    private let pageSize = 50
    private var currentPage = 0
    
    func loadNextPage() {
        guard !isLoading else { return }
        
        isLoading = true
        
        let descriptor = FetchDescriptor<SessionModel>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = pageSize
        descriptor.fetchOffset = currentPage * pageSize
        
        do {
            let newSessions = try modelContext.fetch(descriptor)
            sessions.append(contentsOf: newSessions)
            currentPage += 1
        } catch {
            print("Error loading sessions: \(error)")
        }
        
        isLoading = false
    }
}
```

### 4. Predicate Optimization

**Efficient Querying:**
```swift
extension SessionModel {
    static func recentSessions(limit: Int = 10) -> FetchDescriptor<SessionModel> {
        let descriptor = FetchDescriptor<SessionModel>(
            predicate: #Predicate { session in
                session.createdAt > Calendar.current.date(byAdding: .day, value: -30, to: Date())!
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return descriptor
    }
    
    static func completedSessions() -> FetchDescriptor<SessionModel> {
        return FetchDescriptor<SessionModel>(
            predicate: #Predicate { session in
                session.isCompleted == true
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
    }
    
    static func sessionsWithPendingTranscription() -> FetchDescriptor<SessionModel> {
        return FetchDescriptor<SessionModel>(
            predicate: #Predicate { session in
                session.segments.contains { segment in
                    segment.transcriptionStatus == .pending || segment.transcriptionStatus == .processing
                }
            }
        )
    }
}
```

## Memory Management

### 1. Object Lifecycle Management

**Automatic Cleanup:**
```swift
class StorageManager {
    private let modelContext: ModelContext
    
    func cleanupOldSessions() async {
        let cutoffDate = Calendar.current.date(byAdding: .month, value: -6, to: Date())!
        
        let descriptor = FetchDescriptor<SessionModel>(
            predicate: #Predicate { session in
                session.createdAt < cutoffDate && session.isCompleted == true
            }
        )
        
        do {
            let oldSessions = try modelContext.fetch(descriptor)
            for session in oldSessions {
                // Clean up associated audio files
                await AudioFileManager.shared.deleteAudioFiles(for: session)
                
                // Delete from database
                modelContext.delete(session)
            }
            
            try modelContext.save()
        } catch {
            print("Error during cleanup: \(error)")
        }
    }
}
```

### 2. Memory-Efficient Queries

**Projection Queries for Large Datasets:**
```swift
struct SessionSummary {
    let id: UUID
    let title: String
    let createdAt: Date
    let duration: TimeInterval
    let transcriptionProgress: Double
}

extension SessionModel {
    static func sessionSummaries() -> [SessionSummary] {
        let descriptor = FetchDescriptor<SessionModel>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        
        // Only load necessary fields
        descriptor.propertiesToFetch = [
            \SessionModel.id,
            \SessionModel.title,
            \SessionModel.createdAt,
            \SessionModel.duration
        ]
        
        // Transform to lightweight objects
        return sessions.map { session in
            SessionSummary(
                id: session.id,
                title: session.title,
                createdAt: session.createdAt,
                duration: session.duration,
                transcriptionProgress: session.transcriptionProgress
            )
        }
    }
}
```

## Search and Filtering

### 1. Full-Text Search Implementation

**Efficient Text Search:**
```swift
class SearchManager {
    private let modelContext: ModelContext
    
    func searchTranscriptions(query: String) -> [TranscriptionModel] {
        let descriptor = FetchDescriptor<TranscriptionModel>(
            predicate: #Predicate { transcription in
                transcription.text.localizedStandardContains(query)
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    func searchSessions(query: String) -> [SessionModel] {
        let descriptor = FetchDescriptor<SessionModel>(
            predicate: #Predicate { session in
                session.title.localizedStandardContains(query) ||
                session.notes?.localizedStandardContains(query) == true ||
                session.segments.contains { segment in
                    segment.transcription?.text.localizedStandardContains(query) == true
                }
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}
```



