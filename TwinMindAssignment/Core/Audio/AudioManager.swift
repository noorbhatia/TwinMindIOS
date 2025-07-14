import Foundation
import AVFAudio
import SwiftUI
import Combine
import SwiftData

// MARK: - Recovery Data Structure
private struct RecoveryData: Codable {
    let sessionId: UUID
    let startTime: Date
    let recordingURL: URL?
    let duration: TimeInterval
    let configuration: AudioConfiguration
    let segmentCount: Int
    let isEmergencySave: Bool
    let timestamp: Date
    
    static let recoveryKey = "AudioManager.RecoveryData"
    
    // MARK: - Codable Implementation
    private enum CodingKeys: String, CodingKey {
        case sessionId, startTime, recordingURL, duration, configuration, segmentCount, isEmergencySave, timestamp
    }
    
    init(sessionId: UUID, startTime: Date, recordingURL: URL?, duration: TimeInterval, configuration: AudioConfiguration, segmentCount: Int, isEmergencySave: Bool, timestamp: Date) {
        self.sessionId = sessionId
        self.startTime = startTime
        self.recordingURL = recordingURL
        self.duration = duration
        self.configuration = configuration
        self.segmentCount = segmentCount
        self.isEmergencySave = isEmergencySave
        self.timestamp = timestamp
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decode(UUID.self, forKey: .sessionId)
        startTime = try container.decode(Date.self, forKey: .startTime)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        configuration = try container.decode(AudioConfiguration.self, forKey: .configuration)
        segmentCount = try container.decode(Int.self, forKey: .segmentCount)
        isEmergencySave = try container.decode(Bool.self, forKey: .isEmergencySave)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        
        // Handle URL separately since it needs special encoding/decoding
        if let urlString = try container.decodeIfPresent(String.self, forKey: .recordingURL) {
            recordingURL = URL(string: urlString)
        } else {
            recordingURL = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(duration, forKey: .duration)
        try container.encode(configuration, forKey: .configuration)
        try container.encode(segmentCount, forKey: .segmentCount)
        try container.encode(isEmergencySave, forKey: .isEmergencySave)
        try container.encode(timestamp, forKey: .timestamp)
        
        // Encode URL as string
        if let recordingURL = recordingURL {
            try container.encode(recordingURL.absoluteString, forKey: .recordingURL)
        } else {
            try container.encodeNil(forKey: .recordingURL)
        }
    }
}

/// Central coordinator for all audio recording functionality
@MainActor
final class AudioManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published var currentRecordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0.0
    @Published var audioSamples: [Float] = []
    @Published var recordingState: RecordingState = .stopped
    @Published var isMicPermissionGranted = false
    @Published var currentAudioRoute = "Unknown"
    @Published var isBackgroundRecordingEnabled = false
    @Published var backgroundTimeRemaining: TimeInterval = 0
    @Published var audioConfiguration: AudioConfiguration = .high

    // MARK: - Private Components
    private let audioSession: AudioSessionManager
    private let audioRecorder: AudioRecorderEngine
    private let backgroundTaskManager: BackgroundTaskManager
    private let errorManager: ErrorManager
    private let transcriptionService: TranscriptionService
    private let modelContext: ModelContext
    
    // State management
    private var cancellables = Set<AnyCancellable>()
    private var currentRecordingURL: URL?
    private var recordingStartTime: Date?
    private var isTerminating = false
    
    // Recovery state management
    private var recoverySessionId: UUID?
    private var pendingRecoveryData: RecoveryData?
    
    // MARK: - Initialization
    init(modelContext: ModelContext, errorManager: ErrorManager, transcriptionService:TranscriptionService) {
        // Store dependencies
        self.modelContext = modelContext
        self.errorManager = errorManager
        
        // Initialize core components
        self.audioSession = AudioSessionManager()
        
        self.transcriptionService = transcriptionService
        self.audioRecorder = AudioRecorderEngine(
            audioSession: audioSession,
            transcriptionService: transcriptionService,
            modelContext: modelContext,
            errorManager: errorManager
        )
        self.backgroundTaskManager = BackgroundTaskManager()
        
        setupBindings()
        setupNotificationObservers()
        
        // Check for recovery data from previous session
        checkForRecoveryData()
        
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
            if !isMicPermissionGranted {
                let granted = await audioSession.requestRecordPermission()
                if !granted {
                    reportError(.audio(.microphonePermissionDenied), operation: "startRecording")
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
            recordingStartTime = Date()
            try audioRecorder.startRecording()
            
        } catch {
            reportError(.audio(.recordingStartFailed), operation: "startRecording")
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
        } catch {
            reportError(.audio(.recordingInterrupted), operation: "resumeRecording")
        }
    }
    
    /// Stops recording and returns the file URL
    func stopRecording() -> URL? {
        backgroundTaskManager.endBackgroundTask()
        currentRecordingURL = audioRecorder.stopRecording()
        return currentRecordingURL
    }
    
    /// Gets recording metadata for creating RecordingSession
    func getRecordingMetadata() -> (startTime: Date?, duration: TimeInterval, configuration: AudioConfiguration) {
        return (recordingStartTime, currentRecordingDuration, audioConfiguration)
    }
    
    /// Cancels recording and deletes the file
    func cancelRecording() {
        audioRecorder.cancelRecording()
        backgroundTaskManager.endBackgroundTask()
        currentRecordingURL = nil
        recordingStartTime = nil
    }
    
    // MARK: - Configuration Methods
    
    /// Updates audio recording quality
    func setAudioConfiguration(_ configuration: AudioConfiguration) {
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
        // Guard against invalid or extreme values that could cause Int overflow
        guard duration.isFinite && duration >= 0 && duration <= Double(Int.max) else {
            return "00:00"
        }
        
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
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
    
    // MARK: - Private Methods

    
    private func setupBindings() {
        // Bind audio session properties
        audioSession.$isRecordPermissionGranted
            .assign(to: \.isMicPermissionGranted, on: self)
            .store(in: &cancellables)
        
        audioSession.$currentRoute
            .assign(to: \.currentAudioRoute, on: self)
            .store(in: &cancellables)
        
        // Bind audio recorder properties
        audioRecorder.$currentRecordingDuration
            .assign(to: \.currentRecordingDuration, on: self)
            .store(in: &cancellables)
        
        audioRecorder.$audioLevel
            .assign(to: \.audioLevel, on: self)
            .store(in: &cancellables)
        
        audioRecorder.$audioSamples
            .assign(to: \.audioSamples, on: self)
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
    }
    
    private func setupNotificationObservers() {
        // Audio interruption handling
        NotificationCenter.default.publisher(for: .audioInterruptionBegan)
            .sink { _ in
                // Recording is automatically paused by AudioRecorderEngine
                print("Audio interruption began")
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .audioInterruptionEnded)
            .sink { notification in
                print("Audio interruption ended")
                // Recording resumption is handled by AudioRecorderEngine
            }
            .store(in: &cancellables)
        
        // Audio route changes
        NotificationCenter.default.publisher(for: .audioRouteChanged)
            .sink { notification in
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
            .sink { notification in
                if let userInfo = notification.object as? [String: Any],
                   let timeRemaining = userInfo["timeRemaining"] as? TimeInterval {
                    print("Background time warning: \(timeRemaining) seconds remaining")
                }
            }
            .store(in: &cancellables)
        
        // App termination preparation
        NotificationCenter.default.publisher(for: .prepareForTermination)
            .sink { [weak self] _ in
                self?.handleTerminationPreparation()
            }
            .store(in: &cancellables)
        
        // App will terminate
        NotificationCenter.default.publisher(for: .appWillTerminate)
            .sink { [weak self] notification in
                self?.handleAppTermination(notification)
            }
            .store(in: &cancellables)
    }
    
    private func checkInitialPermissions() async {
        await audioSession.checkRecordPermission()
    }
    
    private func reportError(_ error: ErrorManager.AppError, operation: String) {
        let context = ErrorManager.ErrorContext(
            component: "AudioManager",
            operation: operation,
            userAction: "User attempted audio operation"
        )
        errorManager.reportError(error, context: context)
    }
    
    private func handleAppEnteredBackground() {
        // If recording, request background task
        if recordingState == .recording && !isBackgroundRecordingEnabled {
            let success = backgroundTaskManager.requestBackgroundRecording()
            if !success {
                print("Failed to start background recording task")
                // Save state in case background recording fails
                saveEmergencyRecordingState(isEmergency: false)
            }
        }
        
        // Also request transcription background task if needed
        if !transcriptionService.activeTranscriptions.isEmpty {
            _ = backgroundTaskManager.requestBackgroundTranscription()
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
        
        if recordingState == .recording {
            // Optionally stop recording to save what we have
            // _ = stopRecording()
        }
    }
    
    // MARK: - Termination Handling
    
    private func handleTerminationPreparation() {
        isTerminating = true
        
        // If recording, prepare emergency state save
        if recordingState == .recording {
            saveEmergencyRecordingState()
        }
    }
    
    private func handleAppTermination(_ notification: Notification) {
        isTerminating = true
        
        // Check if this is an emergency termination
        let isEmergency = (notification.object as? [String: Any])?["isEmergency"] as? Bool ?? false
        
        if recordingState == .recording {
            // Emergency save of recording state
            saveEmergencyRecordingState(isEmergency: isEmergency)
            
            // Try to finalize recording quickly if possible
            if isEmergency {
                emergencyFinalizeRecording()
            }
        }
        
        // Clear any pending recovery data if normal termination
        if !isEmergency {
            clearRecoveryData()
        }
    }
    
    private func saveEmergencyRecordingState(isEmergency: Bool = true) {
        guard let startTime = recordingStartTime else { return }
        
        let recoveryData = RecoveryData(
            sessionId: recoverySessionId ?? UUID(),
            startTime: startTime,
            recordingURL: currentRecordingURL,
            duration: currentRecordingDuration,
            configuration: audioConfiguration,
            segmentCount: 0, // This would need to be tracked
            isEmergencySave: isEmergency,
            timestamp: Date()
        )
        
        // Save to UserDefaults for quick access
        if let encoded = try? JSONEncoder().encode(recoveryData) {
            UserDefaults.standard.set(encoded, forKey: RecoveryData.recoveryKey)
            UserDefaults.standard.synchronize()
        }
        
        pendingRecoveryData = recoveryData
    }
    
    private func emergencyFinalizeRecording() {
        // Try to quickly finalize the current recording
        if let recordingURL = audioRecorder.stopRecording() {
            currentRecordingURL = recordingURL
        }
    }
    
    private func checkForRecoveryData() {
        guard let data = UserDefaults.standard.data(forKey: RecoveryData.recoveryKey),
              let recoveryData = try? JSONDecoder().decode(RecoveryData.self, from: data) else {
            return
        }
        
        // Check if recovery data is recent (within last 24 hours)
        let timeSinceRecovery = Date().timeIntervalSince(recoveryData.timestamp)
        guard timeSinceRecovery < 24 * 60 * 60 else {
            clearRecoveryData()
            return
        }
        
        pendingRecoveryData = recoveryData
        recoverySessionId = recoveryData.sessionId
        
        // Notify UI about available recovery data
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .recoveryDataAvailable,
                object: ["recoveryData": recoveryData]
            )
        }
    }
    
    private func clearRecoveryData() {
        UserDefaults.standard.removeObject(forKey: RecoveryData.recoveryKey)
        pendingRecoveryData = nil
        recoverySessionId = nil
    }
    
    // MARK: - Recovery Methods
    
    /// Checks if recovery data is available
    func hasRecoveryData() -> Bool {
        return pendingRecoveryData != nil
    }
    
    /// Gets recovery data information for UI display
    func getRecoveryInfo() -> (duration: TimeInterval, timestamp: Date)? {
        guard let data = pendingRecoveryData else { return nil }
        return (data.duration, data.timestamp)
    }
    
    /// Restores recording session from recovery data
    func restoreFromRecovery() -> Bool {
        guard let recoveryData = pendingRecoveryData else { return false }
        
        // Restore recording state
        recordingStartTime = recoveryData.startTime
        currentRecordingURL = recoveryData.recordingURL
        audioConfiguration = recoveryData.configuration
        recoverySessionId = recoveryData.sessionId
        
        // Clear recovery data after successful restore
        clearRecoveryData()
        
        return true
    }
    
    /// Discards recovery data
    func discardRecoveryData() {
        clearRecoveryData()
    }
}

// MARK: - AudioManager Notification Extensions
extension Notification.Name {
    static let recoveryDataAvailable = Notification.Name("recoveryDataAvailable")
}

// MARK: - Configuration Presets
extension AudioManager {
    
    /// Available audio quality presets
    static let audioQualityPresets: [AudioConfiguration] = [
        .high,
        .medium,
        .low
    ]
    
    /// Gets display name for audio configuration
    func getConfigurationDisplayName(_ config: AudioConfiguration) -> String {
        switch config.sampleRate {
        case 44100: return "High Quality (44.1 kHz)"
        case 22050: return "Medium Quality (22 kHz)"
        case 16000: return "Low Quality (16 kHz)"
        default: 
            // Guard against overflow when converting sample rate to Int
            let sampleRateInKHz = config.sampleRate / 1000
            if sampleRateInKHz.isFinite && sampleRateInKHz <= Double(Int.max) && sampleRateInKHz >= 0 {
                return "Custom (\(Int(sampleRateInKHz)) kHz)"
            } else {
                return "Custom (Unknown kHz)"
            }
        }
    }
} 
