import SwiftUI

struct SettingsView: View {
    let audioManager: AudioManager
    let transcriptionService: TranscriptionService
    
    @State private var showingAPIKeyAlert = false
    @State private var apiKey = ""
    @State private var showingPermissionAlert = false
    
    var body: some View {
        Form {
            // Audio Settings Section
            audioSettingsSection
            
            // Transcription Settings Section
            transcriptionSettingsSection
            
            // System Status Section
            systemStatusSection
            
            // Storage Management Section
            storageManagementSection
            
            // About Section
            aboutSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .alert("OpenAI API Key", isPresented: $showingAPIKeyAlert) {
            TextField("API Key", text: $apiKey)
            Button("Save") {
                _ = KeychainHandler.shared.set(apiKey, forKey: .kOpenAIKey)
//                transcriptionService.configureAPI(apiKey: apiKey)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Enter your OpenAI API key for transcription services")
        }
        .alert("Permission Required", isPresented: $showingPermissionAlert) {
            Button("Open Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Microphone access is required for recording. Please enable it in Settings.")
        }
    }
    
    private var audioSettingsSection: some View {
        Section("Audio Recording") {
            // Microphone Permission
            HStack {
                Label("Microphone Access", systemImage: "mic")
                Spacer()
                Group {
                    if audioManager.isMicPermissionGranted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Button("Grant") {
                            Task {
                                await audioManager.requestMicrophonePermission()
                                if !audioManager.isMicPermissionGranted {
                                    showingPermissionAlert = true
                                }
                            }
                        }
                        .foregroundColor(.blue)
                    }
                }
            }
            
            // Audio Route
            HStack {
                Label("Audio Route", systemImage: "speaker.wave.2")
                Spacer()
                Text(audioManager.currentAudioRoute)
                    .foregroundColor(.secondary)
            }
            
            // Recording Quality
            HStack {
                Label("Recording Quality", systemImage: "waveform")
                Spacer()
                Text(audioManager.getConfigurationDisplayName(audioManager.audioConfiguration))
                    .foregroundColor(.secondary)
            }
            
            // Background Recording
            HStack {
                Label("Background Recording", systemImage: "arrow.triangle.2.circlepath")
                Spacer()
                Group {
                    if audioManager.isBackgroundRecordingSupported() {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.orange)
                    }
                }
            }
            
            if audioManager.isBackgroundRecordingEnabled {
                HStack {
                    Label("Background Time Remaining", systemImage: "clock")
                    Spacer()
                    Text(audioManager.formatDuration(audioManager.backgroundTimeRemaining))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var transcriptionSettingsSection: some View {
        Section("Transcription") {
            // Network Status
            HStack {
                Label("Network Status", systemImage: "network")
                Spacer()
                Group {
                    switch transcriptionService.networkStatus {
                    case .satisfied:
                        HStack {
                            Text("Connected")
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    case .unsatisfied:
                        HStack {
                            Text("Disconnected")
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                    case .requiresConnection:
                        HStack {
                            Text("Limited")
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                        }
                    @unknown default:
                        HStack {
                            Text("Unknown")
                            Image(systemName: "questionmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .font(.caption)
            }
            
            // OpenAI API Configuration
            Button(action: { showingAPIKeyAlert = true }) {
                HStack {
                    Label("OpenAI API Key", systemImage: "key")
                    Spacer()
                    Text("Configure")
                        .foregroundColor(.blue)
                }
            }
            
            // Local Speech Recognition
            HStack {
                Label("Local Speech Recognition", systemImage: "brain")
                Spacer()
                Text("Available")
                    .foregroundColor(.green)
            }
            
            // Active Transcriptions
            if !transcriptionService.activeTranscriptions.isEmpty {
                HStack {
                    Label("Active Transcriptions", systemImage: "clock")
                    Spacer()
                    Text("\(transcriptionService.activeTranscriptions.count)")
                        .foregroundColor(.blue)
                }
            }
            
            // Failed Transcriptions
            if !transcriptionService.failedTranscriptions.isEmpty {
                HStack {
                    Label("Failed Transcriptions", systemImage: "exclamationmark.triangle")
                    Spacer()
                    HStack {
                        Text("\(transcriptionService.failedTranscriptions.count)")
                        Button("Retry") {
                            Task {
                                await transcriptionService.retryFailedTranscriptions()
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }
            }
        }
    }
    
    private var systemStatusSection: some View {
        Section("System Status") {
            // Device Information
            HStack {
                Label("Device", systemImage: "iphone")
                Spacer()
                Text(UIDevice.current.model)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Label("iOS Version", systemImage: "gear")
                Spacer()
                Text(UIDevice.current.systemVersion)
                    .foregroundColor(.secondary)
            }
            
            // App Version
            HStack {
                Label("App Version", systemImage: "app")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
                    .foregroundColor(.secondary)
            }
            
            // Memory Usage (simplified)
            HStack {
                Label("Memory Usage", systemImage: "memorychip")
                Spacer()
                Text("Normal")
                    .foregroundColor(.green)
            }
        }
    }
    
    private var storageManagementSection: some View {
        Section("Storage") {
            // Current recording file size
            HStack {
                Label("Current Recording", systemImage: "doc")
                Spacer()
                Text(audioManager.getRecordingFileSize())
                    .foregroundColor(.secondary)
            }
            
            // Total app storage (placeholder)
            HStack {
                Label("Total App Storage", systemImage: "internaldrive")
                Spacer()
                Text("Calculating...")
                    .foregroundColor(.secondary)
            }
            
            // Available space
            HStack {
                Label("Available Space", systemImage: "externaldrive")
                Spacer()
                Text(getAvailableStorageSpace())
                    .foregroundColor(.secondary)
            }
            
            // Cleanup options
            Button(action: cleanupTempFiles) {
                HStack {
                    Label("Clean Temporary Files", systemImage: "trash")
                    Spacer()
                    Text("Clean")
                        .foregroundColor(.red)
                }
            }
        }
    }
    
    private var aboutSection: some View {
        Section("About") {
            Link(destination: URL(string: "https://openai.com/blog/whisper")!) {
                HStack {
                    Label("OpenAI Whisper", systemImage: "link")
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .foregroundColor(.blue)
                }
            }
            
            HStack {
                Label("Privacy Policy", systemImage: "hand.raised")
                Spacer()
                Text("View")
                    .foregroundColor(.blue)
            }
            
            HStack {
                Label("Support", systemImage: "questionmark.circle")
                Spacer()
                Text("Contact")
                    .foregroundColor(.blue)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func getAvailableStorageSpace() -> String {
        do {
            let fileURL = URL(fileURLWithPath: NSHomeDirectory())
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            
            if let capacity = values.volumeAvailableCapacityForImportantUsage {
                return ByteCountFormatter.string(fromByteCount: capacity, countStyle: .file)
            }
        } catch {
            print("Error getting storage space: \(error)")
        }
        
        return "Unknown"
    }
    
    private func cleanupTempFiles() {
        // This would implement cleanup of temporary files
        // For now, this is a placeholder
        print("Cleaning up temporary files...")
    }
} 
