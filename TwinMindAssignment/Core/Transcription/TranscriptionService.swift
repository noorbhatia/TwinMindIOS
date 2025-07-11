import Foundation
import SwiftData
import Network

/// Service responsible for transcribing audio segments using various transcription providers
@MainActor
final class TranscriptionService: ObservableObject {
    
    // MARK: - Configuration
    struct TranscriptionConfig {
        let maxConcurrentTranscriptions: Int
        let maxRetryAttempts: Int
        let baseRetryDelay: TimeInterval
        let maxRetryDelay: TimeInterval
        let requestTimeout: TimeInterval
        let fallbackThreshold: Int
        
        static let `default` = TranscriptionConfig(
            maxConcurrentTranscriptions: 3,
            maxRetryAttempts: 5,
            baseRetryDelay: 2.0,
            maxRetryDelay: 60.0,
            requestTimeout: 120.0,
            fallbackThreshold: 5
        )
        
        static let aggressive = TranscriptionConfig(
            maxConcurrentTranscriptions: 5,
            maxRetryAttempts: 3,
            baseRetryDelay: 1.0,
            maxRetryDelay: 30.0,
            requestTimeout: 60.0,
            fallbackThreshold: 3
        )
    }
    
    // MARK: - Response Model
    struct TranscriptionResponse:Decodable{
        let text:String
    }
    
    // MARK: - Published Properties
    @Published var isTranscribing = false
    @Published var transcriptionProgress: Double = 0.0
    @Published var activeTranscriptions: Set<UUID> = []
    @Published var failedTranscriptions: Set<UUID> = []
    @Published var networkStatus: NWPath.Status = .satisfied
    
    // MARK: - Private Properties
    private let modelContext: ModelContext
    private let config: TranscriptionConfig
    private let networkMonitor: NWPathMonitor
    private let transcriptionQueue = DispatchQueue(label: "transcription.queue", qos: .userInitiated)
    
    // Task management
    private var transcriptionTasks: [UUID: Task<Void, Never>] = [:]
    private var consecutiveFailures = 0
    private var lastFailureTime: Date?
    
    // Local transcription services
    private lazy var localTranscriptionService = LocalTranscriptionService()
    private let network:NetworkHandlerProtocol
    
    // MARK: - Initialization
    init(
        modelContext: ModelContext,
        config: TranscriptionConfig = .default,
        apiConfig: APIConfig = .default,
        network:NetworkHandlerProtocol = NetworkHandler.shared
    ) {
        self.modelContext = modelContext
        self.config = config
        self.network = network

        // Setup network monitoring
        self.networkMonitor = NWPathMonitor()
        setupNetworkMonitoring()
    }
    
    deinit {
        networkMonitor.cancel()
        // Cancel tasks directly since deinit can't be async
        for task in transcriptionTasks.values {
            task.cancel()
        }
        transcriptionTasks.removeAll()
    }
    
    // MARK: - Public Methods
    /// Transcribes all unprocessed segments for a recording session
    func transcribeSession(_ session: Session) async {
        let unprocessedSegments = session.segments.filter { !$0.isProcessed && $0.shouldRetryTranscription }
        
        guard !unprocessedSegments.isEmpty else { return }
        
        isTranscribing = true
        transcriptionProgress = 0.0
        
        defer {
            isTranscribing = false
            transcriptionProgress = 0.0
        }
        
        await transcribeSegments(unprocessedSegments)
    }
    
    /// Transcribes a single audio segment
    func transcribeSegment(_ segment: AudioSegment) async {
        guard !activeTranscriptions.contains(segment.id) else { return }
        
        activeTranscriptions.insert(segment.id)
        defer {
            activeTranscriptions.remove(segment.id)
        }
        
        let task = Task {
            await performTranscription(for: segment)
        }
        
        transcriptionTasks[segment.id] = task
        await task.value
        transcriptionTasks.removeValue(forKey: segment.id)
    }
    
    /// Cancels all active transcriptions
    func cancelAllTranscriptions() {
        for task in transcriptionTasks.values {
            task.cancel()
        }
        transcriptionTasks.removeAll()
        activeTranscriptions.removeAll()
    }
    
    /// Retries failed transcriptions
    func retryFailedTranscriptions() async {
        let descriptor = FetchDescriptor<AudioSegment>(predicate: AudioSegment.retryableSegmentsPredicate)
        
        do {
            let retryableSegments = try modelContext.fetch(descriptor)
            await transcribeSegments(retryableSegments)
        } catch {
            print("Failed to fetch retryable segments: \(error)")
        }
    }
    
    // MARK: - Private Methods
    
    private func transcribeSegments(_ segments: [AudioSegment]) async {
        let semaphore = AsyncSemaphore(value: config.maxConcurrentTranscriptions)
        let totalSegments = segments.count
        var completedSegments = 0
        
        await withTaskGroup(of: Void.self) { group in
            for segment in segments {
                group.addTask {
                    await semaphore.wait()
                    
                    await self.performTranscription(for: segment)
                    
                    await semaphore.signal()
                    
                    completedSegments += 1
                    await MainActor.run {
                        self.transcriptionProgress = Double(completedSegments) / Double(totalSegments)
                    }
                }
            }
        }
    }
    
    private func performTranscription(for segment: AudioSegment) async {
        segment.startProcessing()
        
        do {
            try modelContext.save()
        } catch {
            print("Failed to save processing start: \(error)")
        }
        
        var lastError: Error?
        
//         Try network-based transcription first
         if shouldUseNetworkTranscription() {
             for attempt in 0..<config.maxRetryAttempts {
                 do {
                     _ = try await transcribeWithOpenAI(segment: segment)
                    
                     // Success - reset consecutive failures
                     consecutiveFailures = 0
                     lastFailureTime = nil
                    
                     segment.completeProcessing()
                     try modelContext.save()
                    
                     return
                    
                 } catch {
                     lastError = error
                    
                     // Record failure
                     segment.recordFailure(reason: error.localizedDescription)
                    
                     // Check if we should retry
                     if attempt < config.maxRetryAttempts - 1 {
                         let delay = calculateRetryDelay(attempt: attempt)
                         try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                     }
                 }
             }
            
             // Network transcription failed - increment consecutive failures
             consecutiveFailures += 1
             lastFailureTime = Date()
         }
        
        // Fallback to local transcription
        do {
            _ = try await transcribeLocally(segment: segment)
            segment.completeProcessing()
            try modelContext.save()
            
        } catch {
            segment.recordFailure(reason: "Network and local transcription failed: \(error.localizedDescription)")
            failedTranscriptions.insert(segment.id)
            
            do {
                try modelContext.save()
            } catch {
                print("Failed to save transcription failure: \(error)")
            }
        }
    }
    
    private func transcribeWithOpenAI(segment: AudioSegment) async throws -> Transcription {
        guard let fileURL = segment.fileURL else {
            throw TranscriptionError.invalidAudioFile
        }
        
        let endpoint = Endpoint(path:  "/audio/transcriptions", method: .POST, queryItems: nil)
        
        let response: TranscriptionResponse = try await network.uploadMultipartFile(fileURL: fileURL, endpoint:endpoint, config: APIConfig.default)
       
        // Create transcription model
        let transcription = Transcription(
            text: response.text,
            confidence: 0.95, // OpenAI doesn't provide confidence scores
            language: "",
            processingMethod: .openaiWhisper,
            apiProvider: "OpenAI",
            modelUsed: "",
            processingDuration: Date().timeIntervalSince(segment.processingStartTime ?? Date()),
            audioSegment: segment
        )
        
        transcription.complete(
            confidence: 0.95,
            language: ""
        )
        
        modelContext.insert(transcription)
        segment.transcription = transcription
        
        return transcription
    }
    
    private func transcribeLocally(segment: AudioSegment) async throws -> Transcription {
        let transcription = try await localTranscriptionService.transcribe(segment: segment)
        
        modelContext.insert(transcription)
        segment.transcription = transcription
        
        return transcription
    }
    
   
    
    private func shouldUseNetworkTranscription() -> Bool {
        // Don't use network if no connectivity
        guard networkStatus == .satisfied else { return false }
        
        // Don't use network if too many consecutive failures
        guard consecutiveFailures < config.fallbackThreshold else { return false }
        
        // Don't use network if recent failure (backoff period)
        if let lastFailure = lastFailureTime,
           Date().timeIntervalSince(lastFailure) < calculateBackoffDelay() {
            return false
        }
        
        return true
    }
    
    private func calculateRetryDelay(attempt: Int) -> TimeInterval {
        let delay = config.baseRetryDelay * pow(2.0, Double(attempt))
        return min(delay, config.maxRetryDelay)
    }
    
    private func calculateBackoffDelay() -> TimeInterval {
        let delay = config.baseRetryDelay * pow(2.0, Double(consecutiveFailures))
        return min(delay, config.maxRetryDelay)
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.networkStatus = path.status
            }
        }
        
        networkMonitor.start(queue: DispatchQueue(label: "network.monitor"))
    }
}

// MARK: - Supporting Types

enum TranscriptionError: LocalizedError {
    case invalidAudioFile
    case apiKeyNotConfigured
    case invalidResponse
    case apiError(Int, String)
    case networkUnavailable
    case localTranscriptionFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidAudioFile:
            return "Invalid audio file for transcription"
        case .apiKeyNotConfigured:
            return "OpenAI API key not configured"
        case .invalidResponse:
            return "Invalid response from transcription service"
        case .apiError(let code, let message):
            return "API Error (\(code)): \(message)"
        case .networkUnavailable:
            return "Network unavailable for transcription"
        case .localTranscriptionFailed:
            return "Local transcription service failed"
        }
    }
}

//struct OpenAITranscriptionResponse: Codable {
//    let text: String
//    let language: String?
//    let duration: Double?
//    let segments: [TranscriptionSegment]?
//    
//    struct TranscriptionSegment: Codable {
//        let id: Int
//        let start: Double
//        let end: Double
//        let text: String
//        let temperature: Double?
//        let avgLogprob: Double?
//        let compressionRatio: Double?
//        let noSpeechProb: Double?
//        
//        private enum CodingKeys: String, CodingKey {
//            case id, start, end, text, temperature
//            case avgLogprob = "avg_logprob"
//            case compressionRatio = "compression_ratio"
//            case noSpeechProb = "no_speech_prob"
//        }
//    }
//}

// MARK: - Async Semaphore

actor AsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    
    init(value: Int) {
        self.value = value
    }
    
    func wait() async {
        if value > 0 {
            value -= 1
            return
        }
        
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
    
    func signal() {
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.resume()
        } else {
            value += 1
        }
    }
} 
