import SwiftUI
import Speech
import SwiftData
import DSWaveformImage
import DSWaveformImageViews

/// Recording controls interface with visual feedback and audio monitoring
struct RecordingControlsView: View {
    @ObservedObject var audioManager: AudioManager
    @Environment(\.modelContext) private var modelContext
    @State private var showingSettingsSheet = false
    @State private var showingPermissionAlert = false
    // Waveform configuration
    @State private var liveConfiguration: Waveform.Configuration = Waveform.Configuration(
        style: .striped(.init(color: .systemRed, width: 3, spacing: 3)),
        scale: 1.0,
        verticalScalingFactor: 0.9
    )

    var body: some View {
        VStack(spacing: 24) {
            // Recording Status and Info
//            recordingStatusSection
            
            // Live Waveform Visualization
            if audioManager.isRecording {
                WaveformView(samples: audioManager.audioSamples)
                    .frame(width: 150, height: 150)
            }
            
            // Main Recording Controls
            recordingControls
            
            // Secondary Controls
            secondaryControls
        }
        .padding(.horizontal, 20)
//        .alert("Microphone Permission Required", isPresented: $showingPermissionAlert) {
//            Button("Settings") {
//                openAppSettings()
//            }
//            Button("Cancel", role: .cancel) { }
//        } message: {
//            Text("This app needs microphone access to record audio. Please enable it in Settings.")
//        }
//        .alert("Recording Error", isPresented: $audioManager.showingErrorAlert) {
//            Button("OK") {
//                audioManager.clearError()
//            }
//            if audioManager.lastError == .permissionDenied {
//                Button("Settings") {
//                    openAppSettings()
//                }
//            }
//        } message: {
//            VStack(alignment: .leading, spacing: 8) {
//                Text(audioManager.getErrorMessage())
//                Text(audioManager.getSuggestedAction())
//                    .font(.caption)
//                    .foregroundColor(.secondary)
//            }
//        }
        .sheet(isPresented: $showingSettingsSheet) {
            RecordingSettingsView(audioManager: audioManager)
        }
        .onReceive(audioManager.$isRecording) { isRecording in
            if !isRecording {
                // Samples are automatically cleared by AudioRecorderEngine
                print("Recording stopped - samples will be cleared by engine")
            }
        }
        .onAppear {
            Task{
                await requestSpeechRecognitionPermission()
            }
        }
    }
    
    func requestSpeechRecognitionPermission() async -> SFSpeechRecognizerAuthorizationStatus {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
    // MARK: - Recording Status Section
    
    private var recordingStatusSection: some View {
        VStack(spacing: 12) {
            // Recording State Indicator
            HStack {
                recordingStateIndicator
                Spacer()
                if audioManager.isBackgroundRecordingEnabled {
                    backgroundRecordingIndicator
                }
            }
            
            // Duration and Route Info
            VStack(spacing: 4) {
                Text(audioManager.formatDuration(audioManager.currentRecordingDuration))
                    .font(.largeTitle.monospacedDigit())
                    .fontWeight(.semibold)
                
                Text("Audio Route: \(audioManager.currentAudioRoute)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var recordingStateIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(recordingStateColor)
                .frame(width: 12, height: 12)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), 
                          value: audioManager.isRecording && !audioManager.isPaused)
            
            Text(recordingStateText)
                .font(.headline)
                .fontWeight(.medium)
        }
    }
    
    private var backgroundRecordingIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundColor(.blue)
                .font(.caption)
            Text("Background")
                .font(.caption)
                .foregroundColor(.blue)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
    
 
    
    // MARK: - Audio Level Meter
    
    private var audioLevelMeter: some View {
        VStack(spacing: 8) {
            Text("Audio Level")
                .font(.caption)
                .foregroundColor(.secondary)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                    
                    // Level indicator
                    RoundedRectangle(cornerRadius: 4)
                        .fill(audioLevelColor)
                        .frame(width: geometry.size.width * CGFloat(audioManager.audioLevel))
                        .animation(.easeOut(duration: 0.1), value: audioManager.audioLevel)
                }
            }
            .frame(height: 8)
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - Recording Controls
    
    private var recordingControls: some View {
        HStack(spacing: 32) {
            // Cancel/Stop Button
            if audioManager.isRecording {
                Button(action: cancelRecording) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.red)
                }
                .disabled(!audioManager.isRecording)
                .buttonStyle(ScaleButtonStyle())
            }
            
            // Main Record/Pause/Resume Button
            Button(action: toggleRecording) {
                Image(systemName: mainButtonIcon)
                    .font(.system(size: 60))
                    .foregroundColor(mainButtonColor)
            }
            .buttonStyle(ScaleButtonStyle())
            
            // Stop Button
            if audioManager.isRecording {
                Button(action: stopRecording) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.gray)
                }
                .disabled(!audioManager.isRecording)
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(.vertical, 20)
    }
    
    // MARK: - Secondary Controls
    
    private var secondaryControls: some View {
        HStack(spacing: 20) {
            // Settings Button
            Button(action: { showingSettingsSheet = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape")
                    Text("Settings")
                }
                .font(.callout)
                .foregroundColor(.blue)
            }
            
            Spacer()
            
            // Permission Status
            if !audioManager.isMicPermissionGranted {
                Button(action: requestPermission) {
                    HStack(spacing: 6) {
                        Image(systemName: "mic.slash")
                        Text("Enable Mic")
                    }
                    .font(.callout)
                    .foregroundColor(.red)
                }
            }
            
            // Recording Quality Indicator
            Text(audioManager.getConfigurationDisplayName(audioManager.audioConfiguration))
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
        }
    }

}

// MARK: - Computed Properties
extension RecordingControlsView{
    private var recordingStateText: String {
        switch audioManager.recordingState {
        case .stopped:
            return "Ready to Record"
        case .recording:
            return audioManager.isPaused ? "Paused" : "Recording"
        case .paused:
            return "Paused"
        case .error:
            return "Error"
        }
    }
    
    private var recordingStateColor: Color {
        switch audioManager.recordingState {
        case .stopped:
            return .gray
        case .recording:
            return audioManager.isPaused ? .orange : .red
        case .paused:
            return .orange
        case .error:
            return .red
        }
    }
    
    private var mainButtonIcon: String {
        if !audioManager.isRecording {
            return "mic.circle.fill"
        } else if audioManager.isPaused {
            return "play.circle.fill"
        } else {
            return "pause.circle.fill"
        }
    }
    
    private var mainButtonColor: Color {
        if !audioManager.isRecording {
            return .gray
        } else if audioManager.isPaused {
            return .green
        } else {
            return .red
        }
    }
    
    private var audioLevelColor: Color {
        let level = audioManager.audioLevel
        if level < 0.3 {
            return .green
        } else if level < 0.7 {
            return .yellow
        } else {
            return .red
        }
    }
}
// MARK: - Actions
extension RecordingControlsView{
    private func toggleRecording() {
        Task {
            if !audioManager.isRecording {
                await audioManager.startRecording()
            } else if audioManager.isPaused {
                audioManager.resumeRecording()
            } else {
                audioManager.pauseRecording()
            }
        }
    }
    
    private func stopRecording() {
        let recordingURL = audioManager.stopRecording()
        let metadata = audioManager.getRecordingMetadata()
        
        // Create and save RecordingSession to SwiftData
        if let url = recordingURL, let startTime = metadata.startTime {
            let config = metadata.configuration
            let endTime = Date()
            
            // Get file size
            let fileSize: Int64
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attributes[.size] as? Int64 {
                fileSize = size
            } else {
                fileSize = 0
            }
            
            // Create RecordingSession
            let session = Session(
                startTime: startTime,
                sampleRate: config.sampleRate,
                bitDepth: Int(config.bitDepth),
                channels: Int(config.channels),
                audioFormat: config.fileFormat.fileExtension.uppercased(),
                audioQuality: getQualityName(for: config)
            )
            
            // Complete the session with file information
            session.complete(
                endTime: endTime,
                fileURL: url,
                fileSize: fileSize,
                wasInterrupted: false, // Could be enhanced to track interruptions
                backgroundRecordingUsed: audioManager.isBackgroundRecordingEnabled
            )
            
            // Save to SwiftData
            modelContext.insert(session)
            
            do {
                try modelContext.save()
                print("Recording session saved: \(session.title)")
            } catch {
                print("Failed to save recording session: \(error)")
            }
        }
    }
    
    private func cancelRecording() {
        audioManager.cancelRecording()
    }
    
    private func requestPermission() {
        Task {
            let granted = await audioManager.requestMicrophonePermission()
            if !granted {
                showingPermissionAlert = true
            }
        }
    }
    
    private func openAppSettings() {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
    }
    
    private func getQualityName(for config: AudioConfiguration) -> String {
        switch config.sampleRate {
        case 44100.0:
            return "High"
        case 22050.0:
            return "Medium"
        case 16000.0:
            return "Low"
        default:
            return "Custom"
        }
    }
    
}

// MARK: - Custom Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Recording Settings View

struct RecordingSettingsView: View {
    @ObservedObject var audioManager: AudioManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedQuality: AudioConfiguration
    
    init(audioManager: AudioManager) {
        self.audioManager = audioManager
        self._selectedQuality = State(initialValue: audioManager.audioConfiguration)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Audio Quality") {
                    ForEach(AudioManager.audioQualityPresets, id: \.sampleRate) { config in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(audioManager.getConfigurationDisplayName(config))
                                    .fontWeight(.medium)
                                Text("\(config.channels) channel, \(config.bitDepth)-bit")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if config.sampleRate == selectedQuality.sampleRate {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedQuality = config
                        }
                    }
                }
                
                Section("Background Recording") {
                    if audioManager.isBackgroundRecordingSupported() {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Background recording is supported")
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.orange)
                                Text("Background recording not configured")
                            }
                            Text("Add 'audio' to UIBackgroundModes in Info.plist")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("App Information") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Build")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Recording Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        audioManager.setAudioConfiguration(selectedQuality)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview


