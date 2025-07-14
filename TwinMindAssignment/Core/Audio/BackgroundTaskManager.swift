import Foundation
import UIKit
import BackgroundTasks

/// Manages background tasks for continuous audio recording with smart prioritization and termination handling
@MainActor
final class BackgroundTaskManager: ObservableObject {
    
    // MARK: - Task Priority Levels
    enum TaskPriority {
        case critical   // Recording tasks
        case high       // Transcription tasks
        case normal     // Background processing
        case low        // Cleanup tasks
    }
    
    // MARK: - Background Task Types
    enum BackgroundTaskType {
        case recording
        case transcription
        case processing
        case cleanup
        
        var priority: TaskPriority {
            switch self {
            case .recording: return .critical
            case .transcription: return .high
            case .processing: return .normal
            case .cleanup: return .low
            }
        }
    }
    
    // MARK: - Task Information
    private struct TaskInfo {
        let identifier: UIBackgroundTaskIdentifier
        let type: BackgroundTaskType
        let startTime: Date
        let expirationHandler: (() -> Void)?
    }
    
    // MARK: - Published Properties
    @Published var isBackgroundRecordingEnabled = false
    @Published var backgroundTimeRemaining: TimeInterval = 0
    @Published var activeTasksCount: Int = 0
    
    // MARK: - Private Properties
    private var activeTasks: [BackgroundTaskType: TaskInfo] = [:]
    private var backgroundAppRefreshTask: BGAppRefreshTask?
    private var backgroundTimer: Timer?
    private var isTerminating = false
    
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
    
    /// Requests background task with specific type and priority
    func requestBackgroundTask(type: BackgroundTaskType) -> Bool {
        guard activeTasks[type] == nil else {
            return true // Already have this type of background task
        }
        
        let taskName = getTaskName(for: type)
        let taskIdentifier = UIApplication.shared.beginBackgroundTask(withName: taskName) { [weak self] in
            self?.handleTaskExpiration(for: type)
        }
        
        if taskIdentifier != .invalid {
            let taskInfo = TaskInfo(
                identifier: taskIdentifier,
                type: type,
                startTime: Date(),
                expirationHandler: nil
            )
            activeTasks[type] = taskInfo
            updatePublishedProperties()
            
            if type == .recording {
                startBackgroundTimer()
            }
            
            return true
        }
        
        return false
    }
    
    /// Requests background recording capability (convenience method)
    func requestBackgroundRecording() -> Bool {
        return requestBackgroundTask(type: .recording)
    }
    
    /// Ends specific background task
    func endBackgroundTask(type: BackgroundTaskType) {
        guard let taskInfo = activeTasks[type] else { return }
        
        UIApplication.shared.endBackgroundTask(taskInfo.identifier)
        activeTasks.removeValue(forKey: type)
        updatePublishedProperties()
        
        if type == .recording {
            stopBackgroundTimer()
        }
    }
    
    /// Ends background recording task (convenience method)
    func endBackgroundTask() {
        endBackgroundTask(type: .recording)
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
        isTerminating = true
        
        // Coordinate emergency data saving across all components
        prepareForTermination()
        
        // Notify all components with termination context
        NotificationCenter.default.post(name: .appWillTerminate, object: ["isEmergency": true])
        
        // Allow brief time for emergency data saving
        let terminationTask = UIApplication.shared.beginBackgroundTask(withName: "Emergency Termination Cleanup") {
            // Force cleanup if time runs out
            self.forceCleanupAllTasks()
        }
        
        // Give components 5 seconds for emergency save
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.forceCleanupAllTasks()
            if terminationTask != .invalid {
                UIApplication.shared.endBackgroundTask(terminationTask)
            }
        }
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
    
    private func getTaskName(for type: BackgroundTaskType) -> String {
        switch type {
        case .recording: return "Audio Recording"
        case .transcription: return "Audio Transcription"
        case .processing: return "Background Processing"
        case .cleanup: return "Resource Cleanup"
        }
    }
    
    private func handleTaskExpiration(for type: BackgroundTaskType) {
        print("Background task expiring for type: \(type)")
        
        switch type {
        case .recording:
            NotificationCenter.default.post(name: .backgroundTaskExpiring, object: ["taskType": "recording"])
        case .transcription:
            NotificationCenter.default.post(name: .backgroundTaskExpiring, object: ["taskType": "transcription"])
        case .processing:
            scheduleBackgroundProcessing()
        case .cleanup:
            break
        }
        
        endBackgroundTask(type: type)
    }
    
    private func updatePublishedProperties() {
        isBackgroundRecordingEnabled = activeTasks[.recording] != nil
        activeTasksCount = activeTasks.count
    }
    
    private func prepareForTermination() {
        // Broadcast termination preparation to all components
        NotificationCenter.default.post(name: .prepareForTermination, object: ["urgency": "high"])
        
        // Stop non-critical timers
        stopBackgroundTimer()
        
        // Mark as terminating to prevent new task requests
        isTerminating = true
    }
    
    private func forceCleanupAllTasks() {
        for (_, taskInfo) in activeTasks {
            UIApplication.shared.endBackgroundTask(taskInfo.identifier)
        }
        activeTasks.removeAll()
        updatePublishedProperties()
        stopBackgroundTimer()
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
    static let prepareForTermination = Notification.Name("prepareForTermination")
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
    
    /// Gets active task information for monitoring
    func getActiveTaskInfo() -> [String: Any] {
        var taskInfo: [String: Any] = [:]
        for (type, info) in activeTasks {
            taskInfo["\(type)"] = [
                "startTime": info.startTime,
                "duration": Date().timeIntervalSince(info.startTime)
            ]
        }
        return taskInfo
    }
    
    /// Checks if termination is in progress
    func isTerminationInProgress() -> Bool {
        return isTerminating
    }
    
    /// Requests background task for transcription
    func requestBackgroundTranscription() -> Bool {
        return requestBackgroundTask(type: .transcription)
    }
    
    /// Ends background transcription task
    func endBackgroundTranscription() {
        endBackgroundTask(type: .transcription)
    }
} 
