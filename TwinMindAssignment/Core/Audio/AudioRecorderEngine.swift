import Foundation
import AVFoundation
import Combine
import Accelerate
import SwiftData

enum AudioFileFormat {
    case wav
    case m4a
    case caf
    
    var fileExtension: String {
        switch self {
        case .wav: return "wav"
        case .m4a: return "m4a"
        case .caf: return "caf"
        }
    }
    
    var audioFileTypeID: AudioFileTypeID {
        switch self {
        case .wav: return kAudioFileWAVEType
        case .m4a: return kAudioFileM4AType
        case .caf: return kAudioFileCAFType
        }
    }
}

// MARK: - Types
enum RecordingState: Equatable {
    case stopped
    case recording
    case paused
    case error(String)
    
    static func == (lhs: RecordingState, rhs: RecordingState) -> Bool {
        switch (lhs, rhs) {
        case
            (.recording, .recording),
            (.paused, .paused),
            (.stopped, .stopped):
            return true
        case (.error(let lhsError), .error(let rhsError)):
            return lhsError == rhsError
        default:
            return false
        }
    }
}

// MARK: - Audio Configuration
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

// MARK: - FFT Configuration Constants
private enum FFTConstants {
    /// Amount of frequency bins to keep after performing the FFT
    static let sampleAmount: Int = 200
    /// Reduce the number of plotted points for visualization
    static let downsampleFactor = 8
    /// Handle high spikes distortion in the waveform
    static let magnitudeLimit: Float = 100
    /// Buffer size for FFT processing
    static let bufferSize = 8192
}

/// Core audio recording engine using AVAudioEngine for high-quality recording
@MainActor
final class AudioRecorderEngine: ObservableObject {
    
    // MARK: - Published Properties
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var currentRecordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0.0
    @Published var audioSamples: [Float] = []
    
    @Published var fftMagnitudes: [Float] = Array(repeating: 0, count: FFTConstants.sampleAmount)
    @Published var recordingState: RecordingState = .stopped
        
    // MARK: - Private Properties
    private let audioSession: AudioSessionManager
    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    private var pauseStartTime: Date?
    private var totalPausedDuration: TimeInterval = 0
    private var currentSegmentIndex = 0
    private var segmentDuration: TimeInterval = 30
    private var segmentTimer: DispatchSourceTimer?
    
    private let transcriptionService: TranscriptionService
    private let modelContext: ModelContext
    private let errorManager: ErrorManager
    
    // Current session tracking
    private var currentSession: Session?
    
    // Audio configuration
    private var audioConfiguration: AudioConfiguration = .high
    
    // File management
    private let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    private var currentRecordingURL: URL?
    
    // Cancellables for Combine
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(
        audioSession: AudioSessionManager,
        transcriptionService: TranscriptionService,
        modelContext: ModelContext,
        errorManager: ErrorManager
    ) {
        self.audioSession = audioSession
        self.transcriptionService = transcriptionService
        self.modelContext = modelContext
        self.errorManager = errorManager
        
        setupAudioEngineObservers()
        setupNotificationObservers()
    }
    
    deinit {
        
    }
    
    // MARK: - Public Methods
    
    /// Configures audio recording settings
    func configureAudio(with configuration: AudioConfiguration) {
        audioConfiguration = configuration
    }
    
    /// Starts audio recording
    func startRecording() throws {
        // Check permissions
        guard audioSession.isRecordPermissionGranted else {
            recordingState = .error("Microphone permission denied")
            reportError(.permission(.microphoneAccessDenied), operation: "startRecording")
            return
        }
        
        // Configure audio session if needed
        if !audioSession.isSessionActive {
            do {
                try audioSession.configureAudioSession()
                try audioSession.activateSession()
            } catch {
                recordingState = .error("Audio session configuration failed")
                reportError(.audio(.audioSessionConfigurationFailed), operation: "startRecording")
                return
            }
        }
        
        // Check storage space
        do {
            try checkStorageSpace()
        } catch {
            recordingState = .error("Insufficient storage space")
            reportError(.storage(.insufficientSpace), operation: "startRecording")
            return
        }
        
        // Create new session
        createNewSession()
        
        // Setup audio engine
        do {
            try setupAudioEngine()
        } catch {
            recordingState = .error("Audio engine setup failed")
            reportError(.audio(.audioEngineFailure), operation: "startRecording")
            return
        }
        
        // Create recording file
        do {
            try createRecordingFile()
        } catch {
            recordingState = .error("Failed to create recording file")
            reportError(.storage(.fileNotFound), operation: "startRecording")
            return
        }
        
        scheduleSegmentTimer()
        
        // Start recording
        do {
            try audioEngine.start()
            isRecording = true
            isPaused = false
            recordingState = .recording
            recordingStartTime = Date()
            totalPausedDuration = 0
            currentSegmentIndex = 0
            
            startRecordingTimer()
            startAudioLevelMonitoring()
            
        } catch {
            recordingState = .error("Failed to start audio engine")
            reportError(.audio(.recordingStartFailed), operation: "startRecording")
        }
    }
    
    /// Pauses audio recording
    func pauseRecording() {
        guard isRecording && !isPaused else { return }
        segmentTimer?.suspend()
        
        audioEngine.pause()
        isPaused = true
        pauseStartTime = Date()
        recordingState = .paused
        
        stopRecordingTimer()
    }
    
    /// Resumes audio recording
    func resumeRecording() throws {
        guard isPaused else { return }
        segmentTimer?.resume()
        do {
            try audioEngine.start()
            isPaused = false
            recordingState = .recording
            
            // Calculate paused duration
            if let pauseStart = pauseStartTime {
                totalPausedDuration += Date().timeIntervalSince(pauseStart)
                pauseStartTime = nil
            }
            
            startRecordingTimer()
            
        } catch {
            recordingState = .error("Failed to resume recording")
            reportError(.audio(.recordingInterrupted), operation: "resumeRecording")
            throw error
        }
    }
    
    /// Stops audio recording and returns the file URL
    func stopRecording() -> URL? {
        guard isRecording else { return nil }
        segmentTimer?.cancel()
        segmentTimer = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        isRecording = false
        isPaused = false
        recordingState = .stopped
        
        stopRecordingTimer()
        stopAudioLevelMonitoring()
        
        // Handle the final segment if there's a current recording
        if let currentURL = currentRecordingURL {
            handleFinishedSegment(currentURL)
        }
        
        // Complete the session
        completeCurrentSession()
        
        audioFile = nil
        
        let recordingURL = currentRecordingURL
        currentRecordingURL = nil
        
        return recordingURL
    }
    
    /// Cancels current recording and deletes the file
    func cancelRecording() {
        let fileURL = stopRecording()
        
        // Delete the recording file
        if let url = fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        
        // Cancel the current session
        if let session = currentSession {
            modelContext.delete(session)
            try? modelContext.save()
            currentSession = nil
        }
        
        currentRecordingDuration = 0
        audioLevel = 0.0
    }
    
    // MARK: - Private Methods
    
    private func reportError(_ error: ErrorManager.AppError, operation: String) {
        let context = ErrorManager.ErrorContext(
            component: "AudioRecorderEngine",
            operation: operation,
            userAction: "User attempted recording operation"
        )
        errorManager.reportError(error, context: context)
    }
    
    /// rotate segment after timer
    private func rotateAudioSegment() {
        guard isRecording, let oldURL = currentRecordingURL else { return }
        handleFinishedSegment(oldURL)
        
        //Create new recording file
        try? createRecordingFile()
    }
    
    private func handleFinishedSegment(_ url: URL) {
        guard let session = currentSession else { return }
        
        // Calculate segment timing
        let segmentStartTime = TimeInterval(currentSegmentIndex) * segmentDuration
        let segmentEndTime = segmentStartTime + segmentDuration
        
        // Create new AudioSegment
        let audioSegment = AudioSegment(
            segmentIndex: currentSegmentIndex,
            startTime: segmentStartTime,
            endTime: segmentEndTime,
            session: session
        )
        
        // Get file size and update segment
        do {
            let fileSize = try getFileSize(url: url)
            audioSegment.updateFile(url: url, size: fileSize)
            
            // Add segment to session and model context
            session.segments.append(audioSegment)
            modelContext.insert(audioSegment)
            
            // Save immediately
            try modelContext.save()
            
            // Queue for transcription
            Task {
                await transcriptionService.transcribeSegment(audioSegment)
            }
            
            // Increment segment index for next segment
            currentSegmentIndex += 1
            
        } catch {
            print("Failed to handle finished segment: \(error)")
            reportError(.storage(.fileNotFound), operation: "handleFinishedSegment")
        }
    }
    
    /// Creates a new recording session
    private func createNewSession() {
        let session = Session(
            startTime: Date(),
            sampleRate: audioConfiguration.sampleRate,
            bitDepth: Int(audioConfiguration.bitDepth),
            channels: Int(audioConfiguration.channels),
            audioFormat: audioConfiguration.fileFormat.fileExtension,
            audioQuality: getQualityString()
        )
        
        currentSession = session
        modelContext.insert(session)
        
        // Save the session immediately to ensure it's persisted
        do {
            try modelContext.save()
            print("Successfully created and saved new session: \(session.title)")
        } catch {
            print("Failed to save new session: \(error)")
            reportError(.data(.saveOperationFailed), operation: "createNewSession")
        }
    }
    
    /// Returns audio quality string based on configuration
    private func getQualityString() -> String {
        switch audioConfiguration.sampleRate {
        case 44100: return "High"
        case 22050: return "Medium"
        case 16000: return "Low"
        default: return "Custom"
        }
    }
    
    /// Gets file size for a given URL
    private func getFileSize(url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }
    
    /// Sets up a repeating timer to call `rotateAudioSegment` every `segmentDuration`.
    private func scheduleSegmentTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + segmentDuration,
                       repeating: segmentDuration)
        timer.setEventHandler { [weak self] in
            self?.rotateAudioSegment()
        }
        timer.resume()
        segmentTimer = timer
    }
    
    private func setupAudioEngine() throws {
        let fmt = audioEngine.inputNode.inputFormat(forBus: 0)
        // Install tap on input node
        audioEngine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buffer, _ in
            Task { @MainActor in
                self?.processAudioBuffer(buffer)
            }
        }
        
        audioEngine.prepare()
    }
    
    private func createRecordingFile() throws {
        let fileName = "recording_\(Date().timeIntervalSince1970).\(audioConfiguration.fileFormat.fileExtension)"
        let fileURL = documentsPath.appendingPathComponent(fileName)
        
        // Create recording format
        let fmt = audioEngine.inputNode.inputFormat(forBus: 0)

        let settings:[String: Any] = [
            AVFormatIDKey:           kAudioFormatLinearPCM,
            AVSampleRateKey:         fmt.sampleRate,
            AVNumberOfChannelsKey:   fmt.channelCount,
            AVLinearPCMBitDepthKey:  16,
            AVLinearPCMIsFloatKey:   false
        ]
        
        do {
            audioFile = try AVAudioFile(forWriting: fileURL, settings: settings)
            currentRecordingURL = fileURL
        } catch {
            reportError(.storage(.fileNotFound), operation: "createRecordingFile")
            throw error
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Write buffer to file
        guard let audioFile = audioFile else { return }
        
        do {
            try audioFile.write(from: buffer)
            // Calculate audio level for real-time monitoring
            calculateAudioLevel(from: buffer)
        } catch {
            print("Failed to write audio buffer: \(error)")
            reportError(.storage(.diskWriteError), operation: "processAudioBuffer")
        }
    }
    
    private func calculateAudioLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        
        // Guard against frame count overflow (though unlikely with UInt32 -> Int conversion)
        guard buffer.frameLength <= Int.max else { return }
        
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }
        
        var sum: Float = 0
        
        for i in 0..<frameCount {
            sum += channelData[i] * channelData[i]
        }
        let rms = sqrt(sum / Float(frameCount))
        let db: Float = rms > 0 ? 20 * log10(rms) : -80
        
        self.audioLevel = db
        self.extractWaveformSamples(db)
    }
    
    private func extractWaveformSamples(_ db: Float) {
        // Normalize for UI display (adjust multiplier as needed)
        let normalized = max(0, min(1, (db + 80) / 80))
        
        // Add to waveform samples
        audioSamples.append(normalized)
        
        // Keep only the last 100 samples for performance
        if audioSamples.count > 10 {
            audioSamples.removeFirst(audioSamples.count - 10)
        }
    }
    
    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateRecordingDuration()
        }
    }
    
    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
    
    private func updateRecordingDuration() {
        guard let startTime = recordingStartTime else { return }
        
        if isPaused {
            // Duration up to when pause started
            if let pauseStart = pauseStartTime {
                currentRecordingDuration = pauseStart.timeIntervalSince(startTime) - totalPausedDuration
            }
        } else {
            // Current duration minus any paused time
            currentRecordingDuration = Date().timeIntervalSince(startTime) - totalPausedDuration
        }
    }
    
    private func startAudioLevelMonitoring() {
        // Audio level monitoring is handled in processAudioBuffer
    }
    
    private func stopAudioLevelMonitoring() {
        audioLevel = 0.0
        audioSamples.removeAll()
        fftMagnitudes = Array(repeating: 0, count: FFTConstants.sampleAmount)
    }
    
    private func checkStorageSpace() throws {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: documentsPath.path),
              let freeSpace = attributes[.systemFreeSize] as? NSNumber else {
            throw NSError(domain: "StorageError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to check storage space"])
        }
        
        // Require at least 100MB of free space
        let requiredSpace: Int64 = 100 * 1024 * 1024
        if freeSpace.int64Value < requiredSpace {
            throw NSError(domain: "StorageError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Insufficient storage space"])
        }
    }
    
    private func setupAudioEngineObservers() {
        // Listen to audio engine configuration changes
        audioEngine.publisher(for: \.isRunning)
            .sink { [weak self] isRunning in
                if !isRunning && self?.isRecording == true {
                    // Handle unexpected engine stop
                    Task { @MainActor in
                        self?.handleEngineStop()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupNotificationObservers() {
        // Handle audio session interruptions
        NotificationCenter.default.publisher(for: .audioInterruptionBegan)
            .sink { [weak self] _ in
                self?.handleAudioInterruption()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .audioInterruptionEnded)
            .sink { [weak self] notification in
                self?.handleAudioInterruptionEnded(notification)
            }
            .store(in: &cancellables)
        
        // Handle audio route changes
        NotificationCenter.default.publisher(for: .audioRouteChanged)
            .sink { [weak self] _ in
                self?.handleAudioRouteChange()
            }
            .store(in: &cancellables)
    }
    
    private func handleEngineStop() {
        if isRecording && !isPaused {
            recordingState = .error("Audio engine stopped unexpectedly")
            reportError(.audio(.audioEngineFailure), operation: "handleEngineStop")
        }
    }
    
    private func handleAudioInterruption() {
        if isRecording && !isPaused {
            pauseRecording()
        }
    }
    
    private func handleAudioInterruptionEnded(_ notification: Notification) {
        guard let userInfo = notification.object as? [String: Any],
              let shouldResume = userInfo["shouldResume"] as? Bool else {
            return
        }
        
        if shouldResume && isPaused && recordingState == .paused {
            try? resumeRecording()
        }
    }
    
    private func handleAudioRouteChange() {
        // Handle route changes during recording
        // For now, continue recording with the new route
        // Could be enhanced to notify user of route changes
    }
    
    private func cleanup() {
        stopRecording()
        try? audioSession.deactivateSession()
        cancellables.removeAll()
    }
    
    /// Completes the current recording session
    private func completeCurrentSession() {
        guard let session = currentSession,
              let fileURL = currentRecordingURL else { return }
        
        do {
            let fileSize = try getFileSize(url: fileURL)
            session.complete(
                endTime: Date(),
                fileURL: fileURL,
                fileSize: fileSize,
                wasInterrupted: recordingState == .paused,
                backgroundRecordingUsed: false // TODO: Track background recording
            )
            
            try modelContext.save()
            currentSession = nil
        } catch {
            print("Failed to complete session: \(error)")
            reportError(.data(.saveOperationFailed), operation: "completeCurrentSession")
        }
    }
}
