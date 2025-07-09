import Foundation
import SwiftUI
import Combine

/// Comprehensive error handling system for the audio recording application
@MainActor
class ErrorManager: ObservableObject {
    
    // MARK: - Error Types
    
    /// Comprehensive error categories covering all app functionality
    enum AppError: Error, Identifiable, Equatable {
        case audio(AudioError)
        case transcription(TranscriptionError)
        case storage(StorageError)
        case network(NetworkError)
        case permission(PermissionError)
        case system(SystemError)
        case data(DataError)
        
        var id: String {
            switch self {
            case .audio(let error): return "audio_\(error.id)"
            case .transcription(let error): return "transcription_\(error.id)"
            case .storage(let error): return "storage_\(error.id)"
            case .network(let error): return "network_\(error.id)"
            case .permission(let error): return "permission_\(error.id)"
            case .system(let error): return "system_\(error.id)"
            case .data(let error): return "data_\(error.id)"
            }
        }
        
        static func == (lhs: AppError, rhs: AppError) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    /// Audio-related errors
    enum AudioError: Error, CaseIterable, Identifiable {
        case microphonePermissionDenied
        case audioSessionConfigurationFailed
        case recordingStartFailed
        case recordingInterrupted
        case audioRouteChangeFailed
        case backgroundRecordingFailed
        case audioEngineFailure
        case audioQualityNotSupported
        case recordingFileCorrupted
        case audioBufferOverflow
        
        var id: String {
            switch self {
            case .microphonePermissionDenied: return "mic_permission_denied"
            case .audioSessionConfigurationFailed: return "session_config_failed"
            case .recordingStartFailed: return "recording_start_failed"
            case .recordingInterrupted: return "recording_interrupted"
            case .audioRouteChangeFailed: return "route_change_failed"
            case .backgroundRecordingFailed: return "background_recording_failed"
            case .audioEngineFailure: return "audio_engine_failure"
            case .audioQualityNotSupported: return "quality_not_supported"
            case .recordingFileCorrupted: return "file_corrupted"
            case .audioBufferOverflow: return "buffer_overflow"
            }
        }
    }
    
    /// Transcription service errors
    enum TranscriptionError: Error, CaseIterable, Identifiable {
        case apiKeyMissing
        case apiKeyInvalid
        case networkConnectionFailed
        case requestTimeout
        case serverError
        case rateLimitExceeded
        case audioFileInvalid
        case transcriptionFailed
        case localTranscriptionUnavailable
        case speechRecognitionPermissionDenied
        case languageNotSupported
        case audioSegmentTooLarge
        
        var id: String {
            switch self {
            case .apiKeyMissing: return "api_key_missing"
            case .apiKeyInvalid: return "api_key_invalid"
            case .networkConnectionFailed: return "network_failed"
            case .requestTimeout: return "request_timeout"
            case .serverError: return "server_error"
            case .rateLimitExceeded: return "rate_limit"
            case .audioFileInvalid: return "audio_invalid"
            case .transcriptionFailed: return "transcription_failed"
            case .localTranscriptionUnavailable: return "local_unavailable"
            case .speechRecognitionPermissionDenied: return "speech_permission_denied"
            case .languageNotSupported: return "language_not_supported"
            case .audioSegmentTooLarge: return "segment_too_large"
            }
        }
    }
    
    /// Storage and file system errors
    enum StorageError: Error, CaseIterable, Identifiable {
        case insufficientSpace
        case fileNotFound
        case fileCorrupted
        case encryptionFailed
        case decryptionFailed
        case filePermissionDenied
        case storageQuotaExceeded
        case diskWriteError
        case directoryCreationFailed
        case fileCleanupFailed
        
        var id: String {
            switch self {
            case .insufficientSpace: return "insufficient_space"
            case .fileNotFound: return "file_not_found"
            case .fileCorrupted: return "file_corrupted"
            case .encryptionFailed: return "encryption_failed"
            case .decryptionFailed: return "decryption_failed"
            case .filePermissionDenied: return "file_permission_denied"
            case .storageQuotaExceeded: return "quota_exceeded"
            case .diskWriteError: return "disk_write_error"
            case .directoryCreationFailed: return "directory_creation_failed"
            case .fileCleanupFailed: return "cleanup_failed"
            }
        }
    }
    
    /// Network-related errors
    enum NetworkError: Error, CaseIterable, Identifiable {
        case noConnection
        case slowConnection
        case connectionTimeout
        case serverUnavailable
        case invalidResponse
        case sslError
        case dnsResolutionFailed
        case proxyError
        
        var id: String {
            switch self {
            case .noConnection: return "no_connection"
            case .slowConnection: return "slow_connection"
            case .connectionTimeout: return "connection_timeout"
            case .serverUnavailable: return "server_unavailable"
            case .invalidResponse: return "invalid_response"
            case .sslError: return "ssl_error"
            case .dnsResolutionFailed: return "dns_failed"
            case .proxyError: return "proxy_error"
            }
        }
    }
    
    /// Permission-related errors
    enum PermissionError: Error, CaseIterable, Identifiable {
        case microphoneAccessDenied
        case speechRecognitionDenied
        case notificationPermissionDenied
        case backgroundAppRefreshDisabled
        case permissionPromptCancelled
        
        var id: String {
            switch self {
            case .microphoneAccessDenied: return "microphone_denied"
            case .speechRecognitionDenied: return "speech_denied"
            case .notificationPermissionDenied: return "notification_denied"
            case .backgroundAppRefreshDisabled: return "background_refresh_disabled"
            case .permissionPromptCancelled: return "permission_cancelled"
            }
        }
    }
    
    /// System-level errors
    enum SystemError: Error, CaseIterable, Identifiable {
        case memoryWarning
        case cpuThrottling
        case batteryLow
        case thermalThrottling
        case appTerminating
        case systemUpdateRequired
        case deviceNotSupported
        
        var id: String {
            switch self {
            case .memoryWarning: return "memory_warning"
            case .cpuThrottling: return "cpu_throttling"
            case .batteryLow: return "battery_low"
            case .thermalThrottling: return "thermal_throttling"
            case .appTerminating: return "app_terminating"
            case .systemUpdateRequired: return "system_update_required"
            case .deviceNotSupported: return "device_not_supported"
            }
        }
    }
    
    /// Data persistence errors
    enum DataError: Error, CaseIterable, Identifiable {
        case databaseCorrupted
        case migrationFailed
        case saveOperationFailed
        case fetchOperationFailed
        case relationshipIntegrityViolation
        case duplicateRecordError
        case invalidModelData
        
        var id: String {
            switch self {
            case .databaseCorrupted: return "database_corrupted"
            case .migrationFailed: return "migration_failed"
            case .saveOperationFailed: return "save_failed"
            case .fetchOperationFailed: return "fetch_failed"
            case .relationshipIntegrityViolation: return "relationship_violation"
            case .duplicateRecordError: return "duplicate_record"
            case .invalidModelData: return "invalid_model_data"
            }
        }
    }
    
    // MARK: - Error Context
    
    /// Additional context information for errors
    struct ErrorContext {
        let component: String
        let operation: String
        let timestamp: Date
        let additionalInfo: [String: Any]
        let stackTrace: String?
        let userAction: String?
        
        init(component: String, operation: String, additionalInfo: [String: Any] = [:], stackTrace: String? = nil, userAction: String? = nil) {
            self.component = component
            self.operation = operation
            self.timestamp = Date()
            self.additionalInfo = additionalInfo
            self.stackTrace = stackTrace
            self.userAction = userAction
        }
    }
    
    // MARK: - Recovery Strategy
    
    /// Automated recovery strategies for different error types
    enum RecoveryStrategy {
        case retry(maxAttempts: Int, backoffMultiplier: Double)
        case fallback(alternative: String)
        case userAction(required: String)
        case restart(component: String)
        case ignore
        case fatal
        
        var description: String {
            switch self {
            case .retry(let max, _):
                return "Retry up to \(max) times"
            case .fallback(let alt):
                return "Use \(alt) as fallback"
            case .userAction(let action):
                return "User must \(action)"
            case .restart(let component):
                return "Restart \(component)"
            case .ignore:
                return "Safe to ignore"
            case .fatal:
                return "Requires app restart"
            }
        }
    }
    
    // MARK: - Published Properties
    
    @Published var currentError: AppError?
    @Published var errorHistory: [ErrorRecord] = []
    @Published var isShowingErrorAlert = false
    @Published var errorAnalytics: ErrorAnalytics = ErrorAnalytics()
    
    // MARK: - Error Record
    
    struct ErrorRecord: Identifiable {
        let id = UUID()
        let error: AppError
        let context: ErrorContext
        let recoveryStrategy: RecoveryStrategy
        let resolved: Bool
        let resolvedAt: Date?
        
        init(error: AppError, context: ErrorContext, recoveryStrategy: RecoveryStrategy) {
            self.error = error
            self.context = context
            self.recoveryStrategy = recoveryStrategy
            self.resolved = false
            self.resolvedAt = nil
        }
    }
    
    // MARK: - Error Analytics
    
    struct ErrorAnalytics {
        var totalErrorCount: Int = 0
        var errorsByCategory: [String: Int] = [:]
        var mostCommonErrors: [String] = []
        var errorRate: Double = 0.0
        var lastAnalysisDate: Date = Date()
        
        mutating func recordError(_ error: AppError) {
            totalErrorCount += 1
            let category = String(describing: error).components(separatedBy: "(").first ?? "unknown"
            errorsByCategory[category, default: 0] += 1
            updateMostCommonErrors()
        }
        
        private mutating func updateMostCommonErrors() {
            mostCommonErrors = errorsByCategory.sorted { $0.value > $1.value }
                .prefix(5)
                .map { $0.key }
        }
    }
    
    // MARK: - Public Methods
    
    /// Report an error with context and automatic recovery handling
    func reportError(_ error: AppError, context: ErrorContext) {
        let strategy = getRecoveryStrategy(for: error)
        let record = ErrorRecord(error: error, context: context, recoveryStrategy: strategy)
        
        errorHistory.append(record)
        errorAnalytics.recordError(error)
        currentError = error
        
        // Log error for debugging
        logError(error, context: context, strategy: strategy)
        
        // Attempt automatic recovery if possible
        handleAutomaticRecovery(for: error, strategy: strategy, context: context)
        
        // Show user alert for errors requiring user attention
        if shouldShowUserAlert(for: error, strategy: strategy) {
            isShowingErrorAlert = true
        }
    }
    
    /// Get user-friendly error message
    func getErrorMessage(for error: AppError) -> String {
        switch error {
        case .audio(let audioError):
            return getAudioErrorMessage(audioError)
        case .transcription(let transcriptionError):
            return getTranscriptionErrorMessage(transcriptionError)
        case .storage(let storageError):
            return getStorageErrorMessage(storageError)
        case .network(let networkError):
            return getNetworkErrorMessage(networkError)
        case .permission(let permissionError):
            return getPermissionErrorMessage(permissionError)
        case .system(let systemError):
            return getSystemErrorMessage(systemError)
        case .data(let dataError):
            return getDataErrorMessage(dataError)
        }
    }
    
    /// Get suggested user action for error resolution
    func getSuggestedAction(for error: AppError) -> String {
        switch error {
        case .audio(let audioError):
            return getAudioErrorAction(audioError)
        case .transcription(let transcriptionError):
            return getTranscriptionErrorAction(transcriptionError)
        case .storage(let storageError):
            return getStorageErrorAction(storageError)
        case .network(let networkError):
            return getNetworkErrorAction(networkError)
        case .permission(let permissionError):
            return getPermissionErrorAction(permissionError)
        case .system(let systemError):
            return getSystemErrorAction(systemError)
        case .data(let dataError):
            return getDataErrorAction(dataError)
        }
    }
    
    /// Clear current error and dismiss alerts
    func clearError() {
        currentError = nil
        isShowingErrorAlert = false
    }
    
    /// Mark error as resolved
    func markErrorResolved(_ errorId: UUID) {
        if let index = errorHistory.firstIndex(where: { $0.id == errorId }) {
            errorHistory[index] = ErrorRecord(
                error: errorHistory[index].error,
                context: errorHistory[index].context,
                recoveryStrategy: errorHistory[index].recoveryStrategy
            )
        }
    }
    
    /// Get recovery strategy for specific error type
    private func getRecoveryStrategy(for error: AppError) -> RecoveryStrategy {
        switch error {
        case .audio(.microphonePermissionDenied):
            return .userAction(required: "enable microphone permission in Settings")
        case .audio(.recordingInterrupted):
            return .retry(maxAttempts: 1, backoffMultiplier: 1.0)
        case .audio(.audioEngineFailure):
            return .restart(component: "audio engine")
        case .transcription(.networkConnectionFailed):
            return .fallback(alternative: "local transcription")
        case .transcription(.apiKeyMissing):
            return .userAction(required: "configure API key in Settings")
        case .transcription(.rateLimitExceeded):
            return .retry(maxAttempts: 3, backoffMultiplier: 2.0)
        case .storage(.insufficientSpace):
            return .userAction(required: "free up storage space")
        case .storage(.encryptionFailed):
            return .retry(maxAttempts: 2, backoffMultiplier: 1.0)
        case .network(.noConnection):
            return .retry(maxAttempts: 5, backoffMultiplier: 1.5)
        case .permission(.microphoneAccessDenied):
            return .userAction(required: "grant microphone permission")
        case .system(.memoryWarning):
            return .restart(component: "app")
        case .data(.databaseCorrupted):
            return .fatal
        default:
            return .retry(maxAttempts: 3, backoffMultiplier: 1.5)
        }
    }
    
    /// Handle automatic recovery attempts
    private func handleAutomaticRecovery(for error: AppError, strategy: RecoveryStrategy, context: ErrorContext) {
        switch strategy {
        case .retry(let maxAttempts, let backoffMultiplier):
            // Implement retry logic with exponential backoff
            Task {
                await performRetryOperation(context: context, maxAttempts: maxAttempts, backoffMultiplier: backoffMultiplier)
            }
        case .fallback(let alternative):
            // Trigger fallback mechanism
            print("Activating fallback: \(alternative)")
        case .restart(let component):
            // Request component restart
            print("Requesting restart of: \(component)")
        case .ignore:
            // Silently ignore this error
            clearError()
        default:
            break
        }
    }
    
    /// Perform retry operation with exponential backoff
    private func performRetryOperation(context: ErrorContext, maxAttempts: Int, backoffMultiplier: Double) async {
        for attempt in 1...maxAttempts {
            let delay = pow(backoffMultiplier, Double(attempt - 1))
            
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            
            // Here you would retry the original operation
            // This is a placeholder - actual retry logic would be implemented
            // by the calling component
            print("Retry attempt \(attempt) for \(context.operation) in \(context.component)")
        }
    }
    
    /// Determine if user alert should be shown
    private func shouldShowUserAlert(for error: AppError, strategy: RecoveryStrategy) -> Bool {
        switch strategy {
        case .userAction, .fatal:
            return true
        case .retry, .restart:
            return false
        case .fallback, .ignore:
            return false
        }
    }
    
    /// Log error for debugging and analytics
    private func logError(_ error: AppError, context: ErrorContext, strategy: RecoveryStrategy) {
        let errorInfo = """
        Error: \(error.id)
        Component: \(context.component)
        Operation: \(context.operation)
        Timestamp: \(context.timestamp)
        Recovery: \(strategy.description)
        """
        
        print("🚨 Error Report:\n\(errorInfo)")
        
        // In production, you might want to send this to analytics service
        // Analytics.track("error_reported", properties: [...])
    }
}

// MARK: - Error Message Implementations
extension ErrorManager {
    
    private func getAudioErrorMessage(_ error: AudioError) -> String {
        switch error {
        case .microphonePermissionDenied:
            return "Microphone access is required to record audio."
        case .audioSessionConfigurationFailed:
            return "Unable to configure audio system. Please restart the app."
        case .recordingStartFailed:
            return "Could not start recording. Please try again."
        case .recordingInterrupted:
            return "Recording was interrupted by another app or phone call."
        case .audioRouteChangeFailed:
            return "Audio device change caused recording issues."
        case .backgroundRecordingFailed:
            return "Background recording is not available."
        case .audioEngineFailure:
            return "Audio system encountered an internal error."
        case .audioQualityNotSupported:
            return "Selected audio quality is not supported on this device."
        case .recordingFileCorrupted:
            return "Recording file appears to be corrupted."
        case .audioBufferOverflow:
            return "Audio buffer overflow - recording may be incomplete."
        }
    }
    
    private func getAudioErrorAction(_ error: AudioError) -> String {
        switch error {
        case .microphonePermissionDenied:
            return "Go to Settings > Privacy & Security > Microphone and enable access for this app."
        case .audioSessionConfigurationFailed:
            return "Close and restart the app, then try recording again."
        case .recordingStartFailed:
            return "Check that no other apps are using the microphone and try again."
        case .recordingInterrupted:
            return "Wait for the interruption to end and tap record again."
        case .audioRouteChangeFailed:
            return "Check your audio device connection and restart recording."
        case .backgroundRecordingFailed:
            return "Enable Background App Refresh in Settings for continuous recording."
        case .audioEngineFailure:
            return "Restart the app and check that your device has sufficient memory."
        case .audioQualityNotSupported:
            return "Select a different audio quality setting in the app settings."
        case .recordingFileCorrupted:
            return "Delete the corrupted recording and record again."
        case .audioBufferOverflow:
            return "Close other apps to free up memory and try recording again."
        }
    }
    
    private func getTranscriptionErrorMessage(_ error: TranscriptionError) -> String {
        switch error {
        case .apiKeyMissing:
            return "Transcription API key is not configured."
        case .apiKeyInvalid:
            return "Transcription API key is invalid or expired."
        case .networkConnectionFailed:
            return "Unable to connect to transcription service."
        case .requestTimeout:
            return "Transcription request timed out."
        case .serverError:
            return "Transcription service is temporarily unavailable."
        case .rateLimitExceeded:
            return "Transcription rate limit exceeded. Please wait before trying again."
        case .audioFileInvalid:
            return "Audio file format is not supported for transcription."
        case .transcriptionFailed:
            return "Transcription failed to process the audio."
        case .localTranscriptionUnavailable:
            return "Local transcription is not available on this device."
        case .speechRecognitionPermissionDenied:
            return "Speech recognition permission is required for local transcription."
        case .languageNotSupported:
            return "Selected language is not supported for transcription."
        case .audioSegmentTooLarge:
            return "Audio segment is too large for transcription service."
        }
    }
    
    private func getTranscriptionErrorAction(_ error: TranscriptionError) -> String {
        switch error {
        case .apiKeyMissing:
            return "Configure your OpenAI API key in Settings."
        case .apiKeyInvalid:
            return "Check and update your API key in Settings."
        case .networkConnectionFailed:
            return "Check your internet connection and try again."
        case .requestTimeout:
            return "Try transcribing smaller audio segments."
        case .serverError:
            return "Wait a few minutes and try again, or use local transcription."
        case .rateLimitExceeded:
            return "Wait for the rate limit to reset or upgrade your API plan."
        case .audioFileInvalid:
            return "Re-record the audio with supported settings."
        case .transcriptionFailed:
            return "Try recording in a quieter environment with clearer audio."
        case .localTranscriptionUnavailable:
            return "Update to a newer iOS version or configure an API key."
        case .speechRecognitionPermissionDenied:
            return "Enable Speech Recognition in Settings > Privacy & Security."
        case .languageNotSupported:
            return "Select a supported language in the transcription settings."
        case .audioSegmentTooLarge:
            return "The app will automatically split large recordings into smaller segments."
        }
    }
    
    private func getStorageErrorMessage(_ error: StorageError) -> String {
        switch error {
        case .insufficientSpace:
            return "Not enough storage space available."
        case .fileNotFound:
            return "Recording file could not be found."
        case .fileCorrupted:
            return "File appears to be corrupted or damaged."
        case .encryptionFailed:
            return "Failed to encrypt recording file."
        case .decryptionFailed:
            return "Failed to decrypt recording file."
        case .filePermissionDenied:
            return "Permission denied accessing recording file."
        case .storageQuotaExceeded:
            return "App storage quota has been exceeded."
        case .diskWriteError:
            return "Failed to save recording to disk."
        case .directoryCreationFailed:
            return "Failed to create necessary directories."
        case .fileCleanupFailed:
            return "Failed to clean up old recording files."
        }
    }
    
    private func getStorageErrorAction(_ error: StorageError) -> String {
        switch error {
        case .insufficientSpace:
            return "Delete some files or apps to free up storage space."
        case .fileNotFound:
            return "Check if the recording was moved or deleted manually."
        case .fileCorrupted:
            return "Delete the corrupted file and record again."
        case .encryptionFailed:
            return "Restart the app and try recording again."
        case .decryptionFailed:
            return "The file may be corrupted. Try restarting the app."
        case .filePermissionDenied:
            return "Restart the app and grant necessary permissions."
        case .storageQuotaExceeded:
            return "Delete old recordings or increase storage limit in Settings."
        case .diskWriteError:
            return "Free up storage space and restart the app."
        case .directoryCreationFailed:
            return "Restart the app with sufficient storage space available."
        case .fileCleanupFailed:
            return "Manually delete old recordings and restart the app."
        }
    }
    
    private func getNetworkErrorMessage(_ error: NetworkError) -> String {
        switch error {
        case .noConnection:
            return "No internet connection available."
        case .slowConnection:
            return "Internet connection is too slow."
        case .connectionTimeout:
            return "Network request timed out."
        case .serverUnavailable:
            return "Service is temporarily unavailable."
        case .invalidResponse:
            return "Received invalid response from server."
        case .sslError:
            return "Secure connection could not be established."
        case .dnsResolutionFailed:
            return "Unable to resolve server address."
        case .proxyError:
            return "Proxy configuration error."
        }
    }
    
    private func getNetworkErrorAction(_ error: NetworkError) -> String {
        switch error {
        case .noConnection:
            return "Check your Wi-Fi or cellular connection and try again."
        case .slowConnection:
            return "Move to an area with better signal or try again later."
        case .connectionTimeout:
            return "Check your internet connection and try again."
        case .serverUnavailable:
            return "Wait a few minutes and try again."
        case .invalidResponse:
            return "Try again later or contact support if the problem persists."
        case .sslError:
            return "Check your device date/time settings and try again."
        case .dnsResolutionFailed:
            return "Check your DNS settings or try a different network."
        case .proxyError:
            return "Check your proxy settings or disable proxy."
        }
    }
    
    private func getPermissionErrorMessage(_ error: PermissionError) -> String {
        switch error {
        case .microphoneAccessDenied:
            return "Microphone access has been denied."
        case .speechRecognitionDenied:
            return "Speech recognition access has been denied."
        case .notificationPermissionDenied:
            return "Notification permission has been denied."
        case .backgroundAppRefreshDisabled:
            return "Background App Refresh is disabled."
        case .permissionPromptCancelled:
            return "Permission request was cancelled."
        }
    }
    
    private func getPermissionErrorAction(_ error: PermissionError) -> String {
        switch error {
        case .microphoneAccessDenied:
            return "Go to Settings > Privacy & Security > Microphone and enable access."
        case .speechRecognitionDenied:
            return "Go to Settings > Privacy & Security > Speech Recognition and enable access."
        case .notificationPermissionDenied:
            return "Go to Settings > Notifications and enable for this app."
        case .backgroundAppRefreshDisabled:
            return "Go to Settings > General > Background App Refresh and enable for this app."
        case .permissionPromptCancelled:
            return "Tap the permission request again and select 'Allow'."
        }
    }
    
    private func getSystemErrorMessage(_ error: SystemError) -> String {
        switch error {
        case .memoryWarning:
            return "Device is running low on memory."
        case .cpuThrottling:
            return "Device performance is being throttled."
        case .batteryLow:
            return "Device battery is critically low."
        case .thermalThrottling:
            return "Device is overheating and performance is reduced."
        case .appTerminating:
            return "App is being terminated by the system."
        case .systemUpdateRequired:
            return "iOS system update is required."
        case .deviceNotSupported:
            return "This device is not supported."
        }
    }
    
    private func getSystemErrorAction(_ error: SystemError) -> String {
        switch error {
        case .memoryWarning:
            return "Close other apps and restart this app."
        case .cpuThrottling:
            return "Let your device cool down and close other apps."
        case .batteryLow:
            return "Connect your device to a charger."
        case .thermalThrottling:
            return "Let your device cool down before continuing."
        case .appTerminating:
            return "Save your work and restart the app."
        case .systemUpdateRequired:
            return "Update your device to the latest iOS version."
        case .deviceNotSupported:
            return "This app requires a newer device model."
        }
    }
    
    private func getDataErrorMessage(_ error: DataError) -> String {
        switch error {
        case .databaseCorrupted:
            return "App database is corrupted."
        case .migrationFailed:
            return "Failed to update app data format."
        case .saveOperationFailed:
            return "Failed to save your recording."
        case .fetchOperationFailed:
            return "Failed to load your recordings."
        case .relationshipIntegrityViolation:
            return "Data consistency error detected."
        case .duplicateRecordError:
            return "Duplicate recording detected."
        case .invalidModelData:
            return "Recording data is invalid."
        }
    }
    
    private func getDataErrorAction(_ error: DataError) -> String {
        switch error {
        case .databaseCorrupted:
            return "Restart the app. If the problem persists, you may need to reset app data."
        case .migrationFailed:
            return "Update to the latest app version and restart."
        case .saveOperationFailed:
            return "Check available storage space and try saving again."
        case .fetchOperationFailed:
            return "Restart the app and check your storage space."
        case .relationshipIntegrityViolation:
            return "Restart the app to repair data consistency."
        case .duplicateRecordError:
            return "Delete the duplicate recording and try again."
        case .invalidModelData:
            return "Delete the invalid recording and record again."
        }
    }
} 