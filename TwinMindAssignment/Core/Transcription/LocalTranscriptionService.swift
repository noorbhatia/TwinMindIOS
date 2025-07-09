import Foundation
import Speech
import AVFoundation

/// Local transcription service using Apple's Speech framework as fallback
@MainActor
final class LocalTranscriptionService: ObservableObject {
    
    // MARK: - Properties
    private let speechRecognizer: SFSpeechRecognizer?
    private var isAvailable = false
    
    // MARK: - Initialization
    init(locale: Locale = Locale.current) {
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
        checkAvailability()
    }
    
    // MARK: - Public Methods
    
    /// Transcribes an audio segment using Apple's Speech framework
    func transcribe(segment: AudioSegment) async throws -> Transcription {
        guard isAvailable else {
            throw LocalTranscriptionError.speechRecognitionNotAvailable
        }
        
        guard let speechRecognizer = speechRecognizer else {
            throw LocalTranscriptionError.speechRecognizerNotInitialized
        }
        
        guard let audioURL = segment.fileURL else {
            throw LocalTranscriptionError.invalidAudioFile
        }
        
        // Check permissions
        let authStatus = await requestSpeechRecognitionPermission()
        guard authStatus == .authorized else {
            throw LocalTranscriptionError.permissionDenied
        }
        
        // Create speech recognition request
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        
        // Set context for better recognition
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        
        let startTime = Date()
        
        // Perform recognition
        return try await withCheckedThrowingContinuation { continuation in
            speechRecognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: LocalTranscriptionError.recognitionFailed(error.localizedDescription))
                    return
                }
                
                guard let result = result, result.isFinal else {
                    return
                }
                
                let processingDuration = Date().timeIntervalSince(startTime)
                
                // Create transcription
                let transcription = Transcription(
                    text: result.bestTranscription.formattedString,
                    confidence: Double(result.bestTranscription.segments.first?.confidence ?? 0.8),
                    language: speechRecognizer.locale.language.languageCode?.identifier,
                    processingMethod: .appleSpeechRecognition,
                    apiProvider: "Apple",
                    modelUsed: "iOS Speech Recognition",
                    processingDuration: processingDuration,
                    audioSegment: segment
                )
                
                transcription.complete(
                    confidence: Double(result.bestTranscription.segments.first?.confidence ?? 0.8),
                    language: speechRecognizer.locale.language.languageCode?.identifier
                )
                
                continuation.resume(returning: transcription)
            }
        }
    }
    
    /// Checks if local transcription is available
    func checkAvailability() {
        guard let speechRecognizer = speechRecognizer else {
            isAvailable = false
            return
        }
        
        isAvailable = speechRecognizer.isAvailable
    }
    
    /// Requests speech recognition permission
    func requestSpeechRecognitionPermission() async -> SFSpeechRecognizerAuthorizationStatus {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
    
    /// Gets the current speech recognition authorization status
    func getSpeechRecognitionAuthorizationStatus() -> SFSpeechRecognizerAuthorizationStatus {
        return SFSpeechRecognizer.authorizationStatus()
    }
    
    /// Gets supported locales for speech recognition
    func getSupportedLocales() -> [Locale] {
        return SFSpeechRecognizer.supportedLocales().sorted { locale1, locale2 in
            locale1.identifier < locale2.identifier
        }
    }
    
    /// Creates a transcription service for a specific locale
    func createServiceForLocale(_ locale: Locale) -> LocalTranscriptionService {
        return LocalTranscriptionService(locale: locale)
    }
}

// MARK: - Error Types

enum LocalTranscriptionError: LocalizedError {
    case speechRecognitionNotAvailable
    case speechRecognizerNotInitialized
    case invalidAudioFile
    case permissionDenied
    case recognitionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .speechRecognitionNotAvailable:
            return "Speech recognition is not available on this device"
        case .speechRecognizerNotInitialized:
            return "Speech recognizer could not be initialized"
        case .invalidAudioFile:
            return "Invalid audio file for local transcription"
        case .permissionDenied:
            return "Speech recognition permission denied"
        case .recognitionFailed(let message):
            return "Speech recognition failed: \(message)"
        }
    }
}

// MARK: - Extensions

extension LocalTranscriptionService {
    
    /// Gets a user-friendly status message for speech recognition availability
    func getStatusMessage() -> String {
        guard let speechRecognizer = speechRecognizer else {
            return "Speech recognition not supported for current locale"
        }
        
        if !speechRecognizer.isAvailable {
            return "Speech recognition temporarily unavailable"
        }
        
        switch getSpeechRecognitionAuthorizationStatus() {
        case .notDetermined:
            return "Speech recognition permission not requested"
        case .denied:
            return "Speech recognition permission denied"
        case .restricted:
            return "Speech recognition restricted on this device"
        case .authorized:
            return "Speech recognition available"
        @unknown default:
            return "Speech recognition status unknown"
        }
    }
    
    /// Checks if the service can perform transcription
    func canTranscribe() -> Bool {
        return isAvailable && 
               speechRecognizer != nil && 
               getSpeechRecognitionAuthorizationStatus() == .authorized
    }
    
    /// Gets the locale display name for the current speech recognizer
    func getLocaleDisplayName() -> String {
        guard let speechRecognizer = speechRecognizer else {
            return "Unknown"
        }
        
        return speechRecognizer.locale.localizedString(forIdentifier: speechRecognizer.locale.identifier) ?? 
               speechRecognizer.locale.identifier
    }
} 