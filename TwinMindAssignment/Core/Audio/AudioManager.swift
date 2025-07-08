import Foundation
import SwiftUI
import Combine

/// Central coordinator for all audio recording functionality
@MainActor
final class AudioManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var currentRecordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0.0
    @Published var recordingState: AudioRecorderEngine.RecordingState = .stopped
    @Published var isPermissionGranted = false
    @Published var currentAudioRoute = "Unknown"
    @Published var isBackgroundRecordingEnabled = false
    @Published var backgroundTimeRemaining: TimeInterval = 0
    @Published var audioConfiguration: AudioRecorderEngine.AudioConfiguration = .high
    
    // Error handling
    @Published var lastError: AudioRecorderEngine.AudioRecordingError?
    @Published var showingErrorAlert = false
    
    // MARK: - Private Components
    private let audioSession: AudioSessionManager
    private let audioRecorder: AudioRecorderEngine
    private let backgroundTaskManager: BackgroundTaskManager
    
    // State management
    private var cancellables = Set<AnyCancellable>()
    private var currentRecordingURL: URL?
    
    // MARK: - Initialization
    init() {
        // Initialize core components
        self.audioSession = AudioSessionManager()
        self.audioRecorder = AudioRecorderEngine(audioSession: audioSession)
        self.backgroundTaskManager = BackgroundTaskManager()
        
        setupBindings()
        setupNotificationObservers()
        
        // Initial permission check
        Task {
            await checkInitialPermissions()
        }
    }
    
    // MARK: - Public Recording Methods
    
    /// Starts a new audio recording session
    func startRecording() async {
        do {
            // Request permissions if needed
            if !isPermissionGranted {
                let granted = await audioSession.requestRecordPermission()
                if !granted {
                    handleError(.permissionDenied)
                    return
                }
            }
            
            // Request background recording if app goes to background
            if backgroundTaskManager.isBackgroundRecordingAvailable() {
                _ = backgroundTaskManager.requestBackgroundRecording()
            }
            
            // Configure audio quality
            audioRecorder.configureAudio(with: audioConfiguration)
            
            // Start recording
            try await audioRecorder.startRecording()
            
        } catch let error as AudioRecorderEngine.AudioRecordingError {
            handleError(error)
        } catch {
            handleError(.audioEngineFailure(error.localizedDescription))
        }
    }
    
    /// Pauses the current recording
    func pauseRecording() {
        audioRecorder.pauseRecording()
    }
    
    /// Resumes a paused recording
    func resumeRecording() {
        do {
            try audioRecorder.resumeRecording()
        } catch let error as AudioRecorderEngine.AudioRecordingError {
            handleError(error)
        } catch {
            handleError(.audioEngineFailure(error.localizedDescription))
        }
    }
    
    /// Stops recording and returns the file URL
    func stopRecording() -> URL? {
        backgroundTaskManager.endBackgroundTask()
        currentRecordingURL = audioRecorder.stopRecording()
        return currentRecordingURL
    }
    
    /// Cancels recording and deletes the file
    func cancelRecording() {
        audioRecorder.cancelRecording()
        backgroundTaskManager.endBackgroundTask()
        currentRecordingURL = nil
    }
    
    // MARK: - Configuration Methods
    
    /// Updates audio recording quality
    func setAudioConfiguration(_ configuration: AudioRecorderEngine.AudioConfiguration) {
        audioConfiguration = configuration
        audioRecorder.configureAudio(with: configuration)
    }
    
    /// Requests microphone permission
    func requestMicrophonePermission() async -> Bool {
        return await audioSession.requestRecordPermission()
    }
    
    /// Checks current permission status
    func checkPermissionStatus() async {
        await audioSession.checkRecordPermission()
    }
    
    // MARK: - Background Recording Methods
    
    /// Checks if background recording is supported
    func isBackgroundRecordingSupported() -> Bool {
        return backgroundTaskManager.isBackgroundRecordingAvailable()
    }
    
    /// Validates background configuration
    func validateBackgroundConfiguration() -> (isValid: Bool, missingModes: [String]) {
        return backgroundTaskManager.validateBackgroundConfiguration()
    }
    
    // MARK: - Utility Methods
    
    /// Formats duration for display
    func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    /// Gets formatted file size
    func getRecordingFileSize() -> String {
        guard let url = currentRecordingURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? Int64 else {
            return "Unknown"
        }
        
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    /// Clears any error state
    func clearError() {
        lastError = nil
        showingErrorAlert = false
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        // Bind audio session properties
        audioSession.$isRecordPermissionGranted
            .assign(to: \.isPermissionGranted, on: self)
            .store(in: &cancellables)
        
        audioSession.$currentRoute
            .assign(to: \.currentAudioRoute, on: self)
            .store(in: &cancellables)
        
        // Bind audio recorder properties
        audioRecorder.$isRecording
            .assign(to: \.isRecording, on: self)
            .store(in: &cancellables)
        
        audioRecorder.$isPaused
            .assign(to: \.isPaused, on: self)
            .store(in: &cancellables)
        
        audioRecorder.$currentRecordingDuration
            .assign(to: \.currentRecordingDuration, on: self)
            .store(in: &cancellables)
        
        audioRecorder.$audioLevel
            .assign(to: \.audioLevel, on: self)
            .store(in: &cancellables)
        
        audioRecorder.$recordingState
            .assign(to: \.recordingState, on: self)
            .store(in: &cancellables)
        
        // Bind background task manager properties
        backgroundTaskManager.$isBackgroundRecordingEnabled
            .assign(to: \.isBackgroundRecordingEnabled, on: self)
            .store(in: &cancellables)
        
        backgroundTaskManager.$backgroundTimeRemaining
            .assign(to: \.backgroundTimeRemaining, on: self)
            .store(in: &cancellables)
        
        // Handle recording state changes
        audioRecorder.$recordingState
            .sink { [weak self] state in
                if case .error(let error) = state {
                    self?.handleError(error)
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupNotificationObservers() {
        // Audio interruption handling
        NotificationCenter.default.publisher(for: .audioInterruptionBegan)
            .sink { [weak self] _ in
                // Recording is automatically paused by AudioRecorderEngine
                print("Audio interruption began")
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .audioInterruptionEnded)
            .sink { [weak self] notification in
                print("Audio interruption ended")
                // Recording resumption is handled by AudioRecorderEngine
            }
            .store(in: &cancellables)
        
        // Audio route changes
        NotificationCenter.default.publisher(for: .audioRouteChanged)
            .sink { [weak self] notification in
                if let userInfo = notification.object as? [String: Any],
                   let reason = userInfo["reason"] as? String {
                    print("Audio route changed: \(reason)")
                    // Continue recording with new route
                }
            }
            .store(in: &cancellables)
        
        // Background app state changes
        NotificationCenter.default.publisher(for: .appEnteredBackground)
            .sink { [weak self] _ in
                self?.handleAppEnteredBackground()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .appEnteringForeground)
            .sink { [weak self] _ in
                self?.handleAppEnteringForeground()
            }
            .store(in: &cancellables)
        
        // Background task expiration
        NotificationCenter.default.publisher(for: .backgroundTaskExpiring)
            .sink { [weak self] _ in
                self?.handleBackgroundTaskExpiring()
            }
            .store(in: &cancellables)
        
        // Background time warning
        NotificationCenter.default.publisher(for: .backgroundTimeWarning)
            .sink { [weak self] notification in
                if let userInfo = notification.object as? [String: Any],
                   let timeRemaining = userInfo["timeRemaining"] as? TimeInterval {
                    print("Background time warning: \(timeRemaining) seconds remaining")
                }
            }
            .store(in: &cancellables)
    }
    
    private func checkInitialPermissions() async {
        await audioSession.checkRecordPermission()
    }
    
    private func handleError(_ error: AudioRecorderEngine.AudioRecordingError) {
        lastError = error
        showingErrorAlert = true
        print("Audio error: \(error.localizedDescription)")
    }
    
    private func handleAppEnteredBackground() {
        // If recording, request background task
        if isRecording && !isBackgroundRecordingEnabled {
            let success = backgroundTaskManager.requestBackgroundRecording()
            if !success {
                print("Failed to start background recording task")
            }
        }
    }
    
    private func handleAppEnteringForeground() {
        // App returning to foreground - background task will be ended automatically
        print("App entering foreground")
    }
    
    private func handleBackgroundTaskExpiring() {
        // Background task is about to expire
        print("Background task expiring - saving state")
        
        // In a production app, you might want to:
        // 1. Save the current recording state
        // 2. Stop recording gracefully
        // 3. Show a notification to the user
        
        if isRecording {
            // Optionally stop recording to save what we have
            // _ = stopRecording()
        }
    }
}

// MARK: - Error Handling Extensions
extension AudioManager {
    
    /// Gets user-friendly error message
    func getErrorMessage() -> String {
        guard let error = lastError else { return "" }
        
        switch error {
        case .permissionDenied:
            return "Microphone access is required to record audio. Please enable it in Settings."
        case .audioSessionNotConfigured:
            return "Audio system could not be configured. Please try again."
        case .fileCreationFailure:
            return "Could not create recording file. Please check available storage."
        case .insufficientStorage:
            return "Insufficient storage space. Please free up space and try again."
        case .audioEngineFailure(let message):
            return "Recording error: \(message)"
        case .interruptionFailure:
            return "Recording was interrupted and could not be resumed."
        }
    }
    
    /// Gets suggested action for error
    func getSuggestedAction() -> String {
        guard let error = lastError else { return "" }
        
        switch error {
        case .permissionDenied:
            return "Go to Settings > Privacy & Security > Microphone and enable access for this app."
        case .insufficientStorage:
            return "Delete some files or apps to free up storage space."
        case .audioSessionNotConfigured, .audioEngineFailure, .interruptionFailure:
            return "Close and restart the app, then try recording again."
        case .fileCreationFailure:
            return "Restart the app and ensure you have sufficient storage space."
        }
    }
}

// MARK: - Configuration Presets
extension AudioManager {
    
    /// Available audio quality presets
    static let audioQualityPresets: [AudioRecorderEngine.AudioConfiguration] = [
        .high,
        .medium,
        .low
    ]
    
    /// Gets display name for audio configuration
    func getConfigurationDisplayName(_ config: AudioRecorderEngine.AudioConfiguration) -> String {
        switch config.sampleRate {
        case 44100: return "High Quality (44.1 kHz)"
        case 22050: return "Medium Quality (22 kHz)"
        case 16000: return "Low Quality (16 kHz)"
        default: return "Custom (\(Int(config.sampleRate / 1000)) kHz)"
        }
    }
} 