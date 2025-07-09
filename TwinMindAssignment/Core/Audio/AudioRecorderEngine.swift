import Foundation
import AVFoundation
import Combine
import Accelerate


enum AudioRecordingError: LocalizedError , Equatable{
    case audioSessionNotConfigured
    case audioEngineFailure(String)
    case fileCreationFailure
    case insufficientStorage
    case permissionDenied
    case interruptionFailure
    
    var errorDescription: String? {
        switch self {
        case .audioSessionNotConfigured:
            return "Audio session is not properly configured"
        case .audioEngineFailure(let message):
            return "Audio engine error: \(message)"
        case .fileCreationFailure:
            return "Failed to create audio file"
        case .insufficientStorage:
            return "Insufficient storage space"
        case .permissionDenied:
            return "Microphone permission denied"
        case .interruptionFailure:
            return "Failed to handle audio interruption"
        }
    }
}

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
enum RecordingState:Equatable {
    case stopped
    case recording
    case paused
    case error(AudioRecordingError)
    
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
    
    // Audio configuration
    private var audioConfiguration: AudioConfiguration = .high
    
    // File management
    private let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    private var currentRecordingURL: URL?
    
    // Cancellables for Combine
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - FFT Setup Properties
    private var fftSetup: FFTSetup?
    private let log2n = vDSP_Length(log2(Float(FFTConstants.bufferSize)))
    private var realParts = [Float](repeating: 0, count: FFTConstants.bufferSize)
    private var imaginaryParts = [Float](repeating: 0, count: FFTConstants.bufferSize)
    private var magnitudes = [Float](repeating: 0, count: FFTConstants.bufferSize / 2)
    
    // MARK: - Initialization
    init(audioSession: AudioSessionManager) {
        self.audioSession = audioSession
        setupFFT()
        setupAudioEngineObservers()
        setupNotificationObservers()
    }
    
    deinit {
        // Destroy FFT setup
        if let setup = fftSetup {
            vDSP_destroy_fftsetup(setup)
        }
    }
    
    // MARK: - Public Methods
    
    /// Sets up the FFT for frequency analysis
    private func setupFFT() {
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        guard fftSetup != nil else {
            print("Failed to create FFT setup")
            return
        }
    }
    
    /// Configures audio recording settings
    func configureAudio(with configuration: AudioConfiguration) {
        audioConfiguration = configuration
    }
    
    /// Starts audio recording
    func startRecording()  throws {
        // Check permissions
        guard audioSession.isRecordPermissionGranted else {
            recordingState = .error(.permissionDenied)
            throw AudioRecordingError.permissionDenied
        }
        
        // Configure audio session if needed
        if !audioSession.isSessionActive {
            do {
                try audioSession.configureAudioSession()
                try audioSession.activateSession()
            } catch {
                recordingState = .error(.audioSessionNotConfigured)
                throw AudioRecordingError.audioSessionNotConfigured
            }
        }
        
        // Check storage space
        try checkStorageSpace()
        
        // Setup audio engine
        try setupAudioEngine()
        
        // Create recording file
        try createRecordingFile()
        
        // Start recording
        do {
            try audioEngine.start()
            isRecording = true
            isPaused = false
            recordingState = .recording
            recordingStartTime = Date()
            totalPausedDuration = 0
            
            startRecordingTimer()
            startAudioLevelMonitoring()
            
        } catch {
            recordingState = .error(.audioEngineFailure(error.localizedDescription))
            throw AudioRecordingError.audioEngineFailure(error.localizedDescription)
        }
    }
    
    /// Pauses audio recording
    func pauseRecording() {
        guard isRecording && !isPaused else { return }
        
        audioEngine.pause()
        isPaused = true
        pauseStartTime = Date()
        recordingState = .paused
        
        stopRecordingTimer()
    }
    
    /// Resumes audio recording
    func resumeRecording() throws {
        guard isPaused else { return }
        
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
            recordingState = .error(.audioEngineFailure(error.localizedDescription))
            throw AudioRecordingError.audioEngineFailure(error.localizedDescription)
        }
    }
    
    /// Stops audio recording and returns the file URL
    func stopRecording() -> URL? {
        guard isRecording else { return nil }
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        isRecording = false
        isPaused = false
        recordingState = .stopped
        
        stopRecordingTimer()
        stopAudioLevelMonitoring()
        
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
        
        currentRecordingDuration = 0
        audioLevel = 0.0
    }
    
    // MARK: - Private Methods
    
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
            throw AudioRecordingError.fileCreationFailure
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
    
//    /// Performs FFT analysis on audio data to extract frequency magnitudes
//    private func performFFTAnalysis(data: UnsafeMutablePointer<Float>, frameLength: Int) {
//        guard let fftSetup = fftSetup else { return }
//        
//        // Ensure we have enough data for FFT
//        let dataCount = min(frameLength, FFTConstants.bufferSize)
//        guard dataCount > 0 else { return }
//        
//        // Copy data to real parts array, pad with zeros if necessary
//        realParts.withUnsafeMutableBufferPointer { realBuffer in
//            // Clear the buffer first
//            realBuffer.baseAddress?.initialize(repeating: 0, count: FFTConstants.bufferSize)
//            // Copy available data
//            memcpy(realBuffer.baseAddress, data, dataCount * MemoryLayout<Float>.size)
//        }
//        
//        // Clear imaginary parts
//        imaginaryParts.withUnsafeMutableBufferPointer { imagBuffer in
//            imagBuffer.baseAddress?.initialize(repeating: 0, count: FFTConstants.bufferSize)
//        }
//        
//        // Create split complex structure for FFT
//        var splitComplex = DSPSplitComplex(
//            realp: &realParts,
//            imagp: &imaginaryParts
//        )
//        
//        // Perform FFT
//        vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
//        
//        // Calculate magnitudes
//        vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(FFTConstants.bufferSize / 2))
//        
//        // Process magnitudes for visualization
//        processMagnitudesForVisualization()
//    }
    
    /// Processes FFT magnitudes for waveform visualization
//    private func processMagnitudesForVisualization() {
//        // Take only the amount we want to display
//        let displayMagnitudes = Array(magnitudes.prefix(FFTConstants.sampleAmount))
//        
//        // Apply magnitude limit to prevent spikes
//        let limitedMagnitudes = displayMagnitudes.map { min($0, FFTConstants.magnitudeLimit) }
//        
//        // Normalize magnitudes for display (0.0 to 1.0 range)
//        let maxMagnitude = limitedMagnitudes.max() ?? 1.0
//        let normalizedMagnitudes = limitedMagnitudes.map {
//            maxMagnitude > 0 ? $0 / maxMagnitude : 0.0
//        }
//        
//        // Downsample for smoother visualization
//        var downsampledMagnitudes: [Float] = []
//        for i in stride(from: 0, to: normalizedMagnitudes.count, by: FFTConstants.downsampleFactor) {
//            let endIndex = min(i + FFTConstants.downsampleFactor, normalizedMagnitudes.count)
//            let chunk = Array(normalizedMagnitudes[i..<endIndex])
//            let average = chunk.reduce(0, +) / Float(chunk.count)
//            downsampledMagnitudes.append(average)
//        }
//        
//        // Update the published property
//        fftMagnitudes = downsampledMagnitudes
//    }
    
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
            throw AudioRecordingError.insufficientStorage
        }
        
        // Require at least 100MB of free space
        let requiredSpace: Int64 = 100 * 1024 * 1024
        if freeSpace.int64Value < requiredSpace {
            throw AudioRecordingError.insufficientStorage
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
            recordingState = .error(.audioEngineFailure("Audio engine stopped unexpectedly"))
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
}
