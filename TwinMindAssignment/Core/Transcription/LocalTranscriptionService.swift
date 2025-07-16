import Foundation
import Speech
import AVFoundation

/// Local transcription service using Apple's Speech framework as fallback
@MainActor
final class LocalTranscriptionService: ObservableObject {
    
    // MARK: - Properties
    private let speechRecognizer: SFSpeechRecognizer?
    @Published private(set) var isAvailable = false
    @Published private(set) var permissionStatus:SFSpeechRecognizerAuthorizationStatus
    private let errorManager: ErrorManager?
    
    // MARK: - Initialization
    init(locale: Locale = Locale.current, errorManager: ErrorManager? = nil, status:SFSpeechRecognizerAuthorizationStatus) {
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
        self.errorManager = errorManager
        self.permissionStatus = status
        checkAvailability()
    }
    
    // MARK: - Public Methods
    
    /// Transcribes an audio segment using Apple's Speech framework
    func transcribe(segment: AudioSegment) async throws -> Transcription {
        guard isAvailable else {
            reportError(.transcription(.localTranscriptionUnavailable), operation: "transcribe")
            throw NSError(domain: "LocalTranscriptionError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognition not available"])
        }
        
        guard let speechRecognizer = speechRecognizer else {
            reportError(.transcription(.localTranscriptionUnavailable), operation: "transcribe")
            throw NSError(domain: "LocalTranscriptionError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer not initialized"])
        }
        
        guard let audioURL = segment.fileURL else {
            reportError(.transcription(.audioFileInvalid), operation: "transcribe")
            throw NSError(domain: "LocalTranscriptionError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid audio file"])
        }
        
        // Validate audio file format for Speech Framework compatibility
        do {
            let audioFile = try AVAudioFile(forReading: audioURL)
            let format = audioFile.fileFormat
            print("LocalTranscription: Audio file format - Sample Rate: \(format.sampleRate)Hz, Channels: \(format.channelCount), File: \(audioURL.lastPathComponent)")
            
            // Check if format is compatible with Speech Framework
            if format.sampleRate < 8000 || format.sampleRate > 48000 {
                print("LocalTranscription: Warning - Sample rate \(format.sampleRate)Hz may not be optimal for Speech Framework")
            }
            
            if format.channelCount > 1 {
                print("LocalTranscription: Warning - Multi-channel audio (\(format.channelCount) channels) may not be optimal for Speech Framework")
            }
            
        } catch {
            print("LocalTranscription: Failed to read audio file format: \(error.localizedDescription)")
            reportError(.transcription(.audioFileInvalid), operation: "transcribe")
            throw NSError(domain: "LocalTranscriptionError", code: 6, userInfo: [NSLocalizedDescriptionKey: "Audio file format validation failed: \(error.localizedDescription)"])
        }
        
        // Check permissions
        let authStatus = await requestSpeechRecognitionPermission()
        guard authStatus == .authorized else {
            reportError(.transcription(.speechRecognitionPermissionDenied), operation: "transcribe")
            throw NSError(domain: "LocalTranscriptionError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Speech recognition permission denied"])
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
            var hasResumed = false
            var recognitionTask: SFSpeechRecognitionTask?
            
            recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                guard !hasResumed else { return }
                
                if let error = error {
                    hasResumed = true
                    self?.reportError(.transcription(.transcriptionFailed), operation: "transcribe")
                    continuation.resume(throwing: NSError(domain: "LocalTranscriptionError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Recognition failed: \(error.localizedDescription)"]))
                    return
                }

                guard let result = result, result.isFinal else {
                    return
                }
                
                hasResumed = true
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
        if permissionStatus == .authorized, isAvailable{
            return
        }
        
        guard let speechRecognizer = speechRecognizer else {
            isAvailable = false
            return
        }
        
        isAvailable = speechRecognizer.isAvailable
    }
    
    /// Requests speech recognition permission
    func requestSpeechRecognitionPermission() async -> SFSpeechRecognizerAuthorizationStatus {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        self.permissionStatus = status
        guard let speechRecognizer = speechRecognizer else {
            isAvailable = false
            return status
        }
        
        isAvailable = speechRecognizer.isAvailable
        return status
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
    
   
    
    // MARK: - Private Methods
    
    private func reportError(_ error: ErrorManager.AppError, operation: String) {
        guard let errorManager = errorManager else { return }
        
        let context = ErrorManager.ErrorContext(
            component: "LocalTranscriptionService",
            operation: operation,
            userAction: "User attempted local transcription"
        )
        errorManager.reportError(error, context: context)
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
