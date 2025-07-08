import Foundation
import UIKit
import BackgroundTasks

/// Manages background tasks for continuous audio recording
@MainActor
final class BackgroundTaskManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published var isBackgroundRecordingEnabled = false
    @Published var backgroundTimeRemaining: TimeInterval = 0
    
    // MARK: - Private Properties
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    private var backgroundAppRefreshTask: BGAppRefreshTask?
    private var backgroundTimer: Timer?
    
    // Background task identifiers (must match Info.plist)
    private let backgroundRecordingTaskIdentifier = "com.twinmind.assignment.background-recording"
    private let backgroundProcessingTaskIdentifier = "com.twinmind.assignment.background-processing"
    
    // MARK: - Initialization
    init() {
        setupBackgroundTaskHandlers()
        setupNotificationObservers()
    }
    
    
    deinit {
//        endBackgroundTask()
    }
    
    // MARK: - Public Methods
    
    /// Requests background recording capability
    func requestBackgroundRecording() -> Bool {
        guard backgroundTaskIdentifier == .invalid else {
            return true // Already have background task
        }
        
        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "Audio Recording") { [weak self] in
            // Background task is about to expire
            self?.handleBackgroundTaskExpiration()
        }
        
        if backgroundTaskIdentifier != .invalid {
            isBackgroundRecordingEnabled = true
            startBackgroundTimer()
            return true
        }
        
        return false
    }
    
    /// Ends background recording task
     func endBackgroundTask() {
        guard backgroundTaskIdentifier != .invalid else { return }
        
        UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
        backgroundTaskIdentifier = .invalid
        isBackgroundRecordingEnabled = false
        stopBackgroundTimer()
    }
    
    /// Schedules background app refresh for processing
    func scheduleBackgroundProcessing() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundProcessingTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes from now
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("Background processing task scheduled")
        } catch {
            print("Failed to schedule background processing: \(error)")
        }
    }
    
    /// Checks if background recording is available
    func isBackgroundRecordingAvailable() -> Bool {
        let backgroundModes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        return backgroundModes.contains("audio")
    }
    
    /// Gets remaining background time
    func getRemainingBackgroundTime() -> TimeInterval {
        guard isBackgroundRecordingEnabled else { return 0 }
        return UIApplication.shared.backgroundTimeRemaining
    }
    
    // MARK: - Private Methods
    
    private func setupBackgroundTaskHandlers() {
        // Register background app refresh handler
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundProcessingTaskIdentifier,
            using: nil
        ) { [weak self] task in
            self?.handleBackgroundProcessingTask(task as! BGAppRefreshTask)
        }
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }
    
    @objc private func appDidEnterBackground() {
        // App entered background - start background task if needed
        if !isBackgroundRecordingEnabled {
            // Only request background task if we're currently recording
            // This should be coordinated with the audio recorder
            NotificationCenter.default.post(name: .appEnteredBackground, object: nil)
        }
    }
    
    @objc private func appWillEnterForeground() {
        // App returning to foreground
        stopBackgroundTimer()
        NotificationCenter.default.post(name: .appEnteringForeground, object: nil)
    }
    
    @objc private func appWillTerminate() {
        // App is about to terminate
        endBackgroundTask()
        NotificationCenter.default.post(name: .appWillTerminate, object: nil)
    }
    
    private func handleBackgroundTaskExpiration() {
        // Background task is about to expire
        print("Background task expiring - attempting to save state")
        
        // Notify other components to save state
        NotificationCenter.default.post(name: .backgroundTaskExpiring, object: nil)
        
        // Schedule background processing for later
        scheduleBackgroundProcessing()
        
        // End the current background task
        endBackgroundTask()
    }
    
    private func handleBackgroundProcessingTask(_ task: BGAppRefreshTask) {
        backgroundAppRefreshTask = task
        
        // Set expiration handler
        task.expirationHandler = { [weak self] in
            self?.backgroundAppRefreshTask?.setTaskCompleted(success: false)
            self?.backgroundAppRefreshTask = nil
        }
        
        // Perform background processing (e.g., transcription, cleanup)
        Task {
            await performBackgroundProcessing()
            
            // Schedule next background refresh
            scheduleBackgroundProcessing()
            
            // Mark task as completed
            task.setTaskCompleted(success: true)
            backgroundAppRefreshTask = nil
        }
    }
    
    private func performBackgroundProcessing() async {
        // Notify other components to perform background work
        NotificationCenter.default.post(name: .performBackgroundProcessing, object: nil)
        
        // Allow time for processing
        try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
    }
    
    private func startBackgroundTimer() {
        backgroundTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateBackgroundTimeRemaining()
            }
        }
    }
    
    private func stopBackgroundTimer() {
        backgroundTimer?.invalidate()
        backgroundTimer = nil
        backgroundTimeRemaining = 0
    }
    
    private func updateBackgroundTimeRemaining() {
        backgroundTimeRemaining = getRemainingBackgroundTime()
        
        // Warn when background time is running low
        if backgroundTimeRemaining < 30 && backgroundTimeRemaining > 0 {
            NotificationCenter.default.post(
                name: .backgroundTimeWarning,
                object: ["timeRemaining": backgroundTimeRemaining]
            )
        }
    }
}

// MARK: - Notification Extensions
extension Notification.Name {
    static let appEnteredBackground = Notification.Name("appEnteredBackground")
    static let appEnteringForeground = Notification.Name("appEnteringForeground")
    static let appWillTerminate = Notification.Name("appWillTerminate")
    static let backgroundTaskExpiring = Notification.Name("backgroundTaskExpiring")
    static let backgroundTimeWarning = Notification.Name("backgroundTimeWarning")
    static let performBackgroundProcessing = Notification.Name("performBackgroundProcessing")
}

// MARK: - Background Recording Extensions
extension BackgroundTaskManager {
    
    /// Provides guidance for Info.plist configuration
    static func getRequiredInfoPlistConfiguration() -> [String: Any] {
        return [
            "UIBackgroundModes": [
                "audio",
                "background-processing",
                "background-fetch"
            ],
            "BGTaskSchedulerPermittedIdentifiers": [
                "com.twinmind.assignment.background-recording",
                "com.twinmind.assignment.background-processing"
            ]
        ]
    }
    
    /// Validates that proper background modes are configured
    func validateBackgroundConfiguration() -> (isValid: Bool, missingModes: [String]) {
        let backgroundModes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        let requiredModes = ["audio", "background-processing"]
        
        let missingModes = requiredModes.filter { !backgroundModes.contains($0) }
        
        return (missingModes.isEmpty, missingModes)
    }
} 
