import Foundation
import AVFoundation
import AVFAudio

/// Manages AVAudioSession configuration and state for audio recording
@MainActor
final class AudioSessionManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published var isSessionActive = false
    @Published var currentRoute: String = "Unknown"
    @Published var isRecordPermissionGranted = false
    
    // MARK: - Private Properties
    private let audioSession = AVAudioSession.sharedInstance()
    private var sessionObservers: [NSObjectProtocol] = []
    private var isTerminating = false
    
    // MARK: - Audio Session Configuration
    private let audioSessionCategory: AVAudioSession.Category = .playAndRecord
    private let audioSessionOptions: AVAudioSession.CategoryOptions = [
        .defaultToSpeaker,
        .allowBluetooth,
        .allowBluetoothA2DP,
        .allowAirPlay
    ]
    private let audioSessionMode: AVAudioSession.Mode = .default
    
    // MARK: - Initialization
    init() {
        setupAudioSessionObservers()
        setupTerminationObservers()
        updateCurrentRoute()
        Task {
            await checkRecordPermission()
        }
    }
    
    deinit {
        // Clean up resources synchronously for deinit
        // Note: This is best effort cleanup since we can't call MainActor methods
        cleanupResourcesSync()
    }
    
    // MARK: - Public Methods
    
    /// Configures and activates the audio session for recording
    func configureAudioSession() throws {
        try audioSession.setCategory(
            audioSessionCategory,
            mode: audioSessionMode,
            options: audioSessionOptions
        )
        
        // Set preferred sample rate and I/O buffer duration for optimal performance
        try audioSession.setPreferredSampleRate(44_100)
        try audioSession.setPreferredIOBufferDuration(0.01) // 10ms buffer for low latency
    }
    
    /// Activates the audio session
    func activateSession() throws {
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        isSessionActive = true
    }
    
    /// Deactivates the audio session
    func deactivateSession() throws {
        try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        isSessionActive = false
    }
    
    /// Requests microphone permission
    func requestRecordPermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            // Using deprecated API with suppression since AVAudioApplication is not working as expected
            audioSession.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    self.isRecordPermissionGranted = granted
                    continuation.resume(returning: granted)
                }
            }
        }
    }
    
    /// Checks current microphone permission status
    func checkRecordPermission() async {
        // Using deprecated API with suppression since AVAudioApplication is not working as expected
        let permission = audioSession.recordPermission
        isRecordPermissionGranted = (permission == .granted)
    }
    
    // MARK: - Private Methods
    
    private func setupAudioSessionObservers() {
        // Audio session interruption observer
        let interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAudioSessionInterruption(notification)
            }
        }
        
        // Audio route change observer
        let routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAudioRouteChange(notification)
            }
        }
        
        sessionObservers = [interruptionObserver, routeChangeObserver]
    }
    
    private func removeAudioSessionObservers() {
        sessionObservers.forEach { observer in
            NotificationCenter.default.removeObserver(observer)
        }
        sessionObservers.removeAll()
    }
    
    private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            // Audio session was interrupted
            isSessionActive = false
            NotificationCenter.default.post(name: .audioInterruptionBegan, object: nil)
            
        case .ended:
            // Audio session interruption ended
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    // Attempt to resume audio session
                    do {
                        try activateSession()
                        NotificationCenter.default.post(name: .audioInterruptionEnded, object: ["shouldResume": true])
                    } catch {
                        print("Failed to reactivate audio session after interruption: \(error)")
                        NotificationCenter.default.post(name: .audioInterruptionEnded, object: ["shouldResume": false])
                    }
                }
            }
            
        @unknown default:
            break
        }
    }
    
    private func handleAudioRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        updateCurrentRoute()
        
        NotificationCenter.default.post(name: .audioRouteChanged, object: reason)
    }
    
    private func updateCurrentRoute() {
        let route = audioSession.currentRoute
        if let output = route.outputs.first {
            currentRoute = output.portName
        } else {
            currentRoute = "Unknown"
        }
    }
    
    private func setupTerminationObservers() {
        // App termination preparation observer
        let terminationObserver = NotificationCenter.default.addObserver(
            forName: .prepareForTermination,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleTerminationPreparation()
            }
        }
        
        // App will terminate observer
        let appTerminationObserver = NotificationCenter.default.addObserver(
            forName: .appWillTerminate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppTermination()
            }
        }
        
        sessionObservers.append(terminationObserver)
        sessionObservers.append(appTerminationObserver)
    }
    
    private func handleTerminationPreparation() {
        isTerminating = true
        
        // Prepare for graceful audio session cleanup
        print("AudioSessionManager: Preparing for termination")
    }
    
    private func handleAppTermination() {
        isTerminating = true
        
        // Emergency audio session cleanup
        emergencyCleanup()
    }
    
    private func emergencyCleanup() {
        do {
            // Deactivate audio session quickly
            try audioSession.setActive(false, options: [])
            isSessionActive = false
            print("AudioSessionManager: Emergency cleanup completed")
        } catch {
            print("AudioSessionManager: Emergency cleanup failed: \(error)")
        }
    }
    
    // MARK: - Termination-Safe Methods
    
    /// Safely deactivates session considering termination state
    func safeDeactivateSession() throws {
        guard !isTerminating else {
            // Use emergency cleanup during termination
            emergencyCleanup()
            return
        }
        
        try deactivateSession()
    }
    
    /// Checks if session manager is in termination state
    func isInTerminationState() -> Bool {
        return isTerminating
    }
    
    // MARK: - Non-Isolated Cleanup Methods (for deinit)
    
    /// Non-isolated cleanup for deinit - best effort cleanup
    nonisolated private func cleanupResourcesSync() {
        // Clean up audio session directly (best effort)
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [])
            print("AudioSessionManager: Emergency cleanup completed in deinit")
        } catch {
            print("AudioSessionManager: Emergency cleanup failed in deinit: \(error)")
        }
        
        // Note: Observer cleanup should ideally happen on MainActor
        // but we can't call MainActor methods from deinit
        // The observers will be cleaned up when the object is deallocated
    }
}

// MARK: - Notification Extensions
extension Notification.Name {
    static let audioInterruptionBegan = Notification.Name("audioInterruptionBegan")
    static let audioInterruptionEnded = Notification.Name("audioInterruptionEnded")
    static let audioRouteChanged = Notification.Name("audioRouteChanged")
} 
