# Audio System Design

## Overview

The TwinMindAssignment audio system is built on AVAudioEngine and designed to handle production-level audio recording challenges including route changes, interruptions, background recording, and real-time processing. The system prioritizes reliability, performance, and user experience while maintaining high audio quality.

## Core Architecture

### Audio Engine Stack

```
┌─────────────────────────────────────────────┐
│                UI Layer                      │
│      (Recording Controls, Waveform)         │
├─────────────────────────────────────────────┤
│              AudioManager                    │
│    (Coordination, State Management)         │
├─────────────────────────────────────────────┤
│         AudioRecorderEngine                 │
│    (AVAudioEngine, Recording Logic)         │
├─────────────────────────────────────────────┤
│        AudioSessionManager                  │
│    (Session Config, Route Changes)          │
├─────────────────────────────────────────────┤
│          AVAudioSession                     │
│       (iOS Audio Framework)                 │
└─────────────────────────────────────────────┘
```

### Key Components

#### 1. AudioManager
**Primary Responsibilities:**
- Coordinates all audio operations
- Manages recording state and lifecycle
- Handles communication with transcription services
- Provides UI-bindable state through @Published properties

```swift
@MainActor
final class AudioManager: ObservableObject {
    @Published var currentRecordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0.0
    @Published var audioSamples: [Float] = []
    @Published var recordingState: RecordingState = .stopped
    @Published var isMicPermissionGranted = false
    @Published var currentAudioRoute = "Unknown"
    @Published var isBackgroundRecordingEnabled = false
    @Published var backgroundTimeRemaining: TimeInterval = 0
    @Published var audioConfiguration: AudioConfiguration = .high
    
    // Core functionality
    func startRecording() async
    func pauseRecording()
    func resumeRecording()
    func stopRecording() -> URL?
    func cancelRecording()
}



#### 2. AudioRecorderEngine
**Core Audio Processing:**
- AVAudioEngine setup and configuration
- Audio buffer management and processing
- Real-time audio level monitoring
- File writing and format handling
- Automatic segmentation every 30 seconds
- Integration with transcription services

```swift
class AudioRecorderEngine {
    @Published var currentRecordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0.0
    @Published var audioSamples: [Float] = []
    @Published var recordingState: RecordingState = .stopped
    
    // Core recording methods
    func startRecording() async throws
    func pauseRecording()
    func resumeRecording() throws
    func stopRecording() -> URL?
    func cancelRecording()
    
    // Configuration
    func configureAudio(with configuration: AudioConfiguration)
}


#### 3. AudioSessionManager
**Session Configuration and Monitoring:**
- Audio session category management
- Route change detection and handling
- Interruption management
- Background capability configuration
- Permission management

```swift
class AudioSessionManager: ObservableObject {
    @Published var isRecordPermissionGranted = false
    @Published var currentRoute = "Unknown"
    
    // Core methods
    func requestRecordPermission() async -> Bool
    func checkRecordPermission() async
    func configureAudioSession() throws
    func handleRouteChange(_ notification: Notification)
    func handleInterruption(_ notification: Notification)
}


## Audio Session Management

### Session Categories and Modes

**Recording Configuration:**
```swift
func configureForRecording() throws {
    try audioSession.setCategory(.record, 
                                mode: .default,
                                options: [.defaultToSpeaker, .allowBluetooth])
    try audioSession.setActive(true)
}
```



## Route Change Handling

### Route Change Detection

**Monitoring Route Changes:**
```swift
func setupRouteChangeObserver() {
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleRouteChange),
        name: AVAudioSession.routeChangeNotification,
        object: audioSession
    )
}

@objc private func handleRouteChange(_ notification: Notification) {
    guard let userInfo = notification.userInfo,
          let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
          let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
        return
    }
    
    switch reason {
    case .newDeviceAvailable:
        handleNewDeviceAvailable()
    case .oldDeviceUnavailable:
        handleOldDeviceUnavailable()
    case .categoryChange:
        handleCategoryChange()
    case .override:
        handleOverride()
    default:
        break
    }
}
```

### Route Change Scenarios

#### 1. Headphone Connection/Disconnection
#### 2. Bluetooth Device Changes
#### 3. External Microphone Detection

**RouteChange Observer Setup:**
```swift
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] n in
                self?.handleAudioRouteChange(n)
            }
            .store(in: &cancellables)
 private func handleAudioRouteChange(_ n:Notification) {
        guard recordingState == .recording,
              let raw = n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
              [.oldDeviceUnavailable, .newDeviceAvailable].contains(reason)
        else { return }
        
         recoverAudioEngine()
    }
```

## Interruption Handling

### Interruption Detection and Response

**Interruption Observer Setup:**
```swift
NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] notification in
                self?.handleAudioInterruption(notification)
            }
            .store(in: &cancellables)

private func handleAudioInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else { return }
        switch type {
        case .began:
            if recordingState == .recording {
                pauseRecording()
            }
        case .ended:
            // Resume if possible
            let optsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let opts = AVAudioSession.InterruptionOptions(rawValue: optsRaw)
            if opts.contains(.shouldResume) && recordingState == .paused {
                try? resumeRecording()
            }
        @unknown default:
            break
        }
        
    }
```

### Interruption Scenarios

#### 1. Phone Call Interruption
#### 2. Siri Interruption
#### 3. Notification Interruption



### Interruption Recovery

**Automatic Recovery Strategy:**
```swift
private func recoverAudioEngine() {
        DispatchQueue.main.asyncAfter(deadline:  .now() + 0.1){
            do{
                if let currentURL = self.currentRecordingURL {
                                self.handleFinishedSegment(currentURL)
                            }
                self.audioEngine.pause()
                self.audioEngine.stop()
                self.removeTapSafely()
                self.audioEngine.reset()
                
                try self.setupAudioEngine()
                try self.audioEngine.start()
                self.recordingState = .recording
            }catch{
                print("Recovery failed:", error)
                self.recordingState = .error("Audio engine recovery failed")
                            self.reportError(.audio(.audioEngineFailure), operation: "recoverAudioEngine")
            }
        }
    }
```

## Audio Quality Management

### Recording Format Configuration

```swift

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
```

## Error Handling and Recovery

### Audio System Errors

**Comprehensive Error Handling:**
```swift
enum AudioError: Error {
    case sessionConfigurationFailed
    case engineStartFailed
    case recordingPermissionDenied
    case audioUnavailable
    case formatNotSupported
    case fileWriteError
    case interruption(reason: String)
    case routeChangeError
}

func handleAudioError(_ error: AudioError) {
    switch error {
    case .sessionConfigurationFailed:
        // Try alternative configuration
        fallbackToBasicConfiguration()
    case .engineStartFailed:
        // Restart engine with delay
        scheduleEngineRestart()
    case .recordingPermissionDenied:
        // Request permission again
        requestMicrophonePermission()
    case .audioUnavailable:
        // Show user-friendly error message
        showAudioUnavailableError()
    default:
        // Log error and notify user
        logError(error)
        showGenericAudioError()
    }
}
```