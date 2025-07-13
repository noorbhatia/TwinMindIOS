# TwinMindAssignment - iOS Audio Recording App

## ✨ Features

### Core Features
- **Robust Audio Recording**: Production-ready recording system using AVAudioEngine
- **Intelligent Segmentation**: Automatic splitting into configurable time segments (default: 30 seconds)
- **Backend Transcription**: Integration with OpenAI Whisper API for accurate transcription
- **Local Fallback**: Automatic fallback to Apple's Speech Framework when backend fails
- **Background Recording**: Continues recording when app enters background
- **Real-time Monitoring**: Live audio level visualization and waveform display

### Advanced Features
- **Audio Route Change Handling**: Graceful handling of headphone/Bluetooth connections
- **Interruption Recovery**: Automatic resumption after calls, notifications, and Siri
- **Offline Queuing**: Queue segments for transcription when network is unavailable
- **Retry Logic**: Exponential backoff for failed transcription requests
- **Data Persistence**: Efficient storage using SwiftData with optimized relationships
- **Search & Filter**: Text search across sessions/transcriptions with date filtering

## 📋 Requirements

### System Requirements
- iOS 17.0+ (SwiftData requirement)
- Xcode 15.0+
- Swift 5.9+

### Device Requirements
- iPhone/iPad with microphone access
- Minimum 1GB available storage (for audio files)
- Network connectivity for transcription services

### API Requirements
- OpenAI API key for Whisper transcription service
- Backend transcription endpoint (configurable)

## 🚀 Setup Instructions

### 1. Clone the Repository
```bash
git clone https://github.com/your-username/TwinMindAssignment.git
cd TwinMindAssignment
```


### 3. Set Up Keychain (Optional)
For secure API key storage, the app uses Keychain Services. Keys are automatically stored securely on first run.
Add your OpenAI API key from the settings to use Whisper

### 4. Configure App Permissions
The app requires microphone access. Ensure the following is in `Info.plist`:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs access to the microphone to record audio notes.</string>
```

### 5. Background App Refresh (Optional)
For background recording, enable Background App Refresh:
1. Go to iOS Settings > General > Background App Refresh
2. Enable for TwinMindAssignment

### 6. Build and Run
1. Open `TwinMindAssignment.xcodeproj` in Xcode
2. Select your target device/simulator
3. Press `Cmd + R` to build and run

## 🏗️ Architecture

### Project Structure
```
TwinMindAssignment/
├── Core/                          # Core business logic
│   ├── Audio/                     # Audio recording and processing
│   ├── Transcription/             # Local and remote transcription
│   ├── Network/                   # API communication
│   ├── Storage/                   # File and data management
│   └── Error/                     # Error handling
├── Models/                        # SwiftData models
├── UI/                           # User interface components
│   ├── Components/               # Reusable UI components
│   ├── Recording/                # Recording interface
│   ├── Sessions/                 # Session management UI
│   └── Settings/                 # App settings
└── Utils/                        # Utilities and constants
```

### Key Components

#### AudioManager
- Handles audio recording using AVAudioEngine
- Manages audio session configuration
- Processes audio interruptions and route changes
- Supports background recording

#### TranscriptionService
- Integrates with OpenAI Whisper API
- Implements retry logic with exponential backoff
- Handles network failures and offline queuing
- Falls back to local Speech Framework when needed

#### SwiftData Models
- `SessionModel`: Recording sessions with metadata
- `SegmentModel`: Audio segments with transcription data
- `TranscriptionModel`: Transcription results and status

## 🎮 Usage

### Recording Audio
1. Tap the record button to start recording
2. Audio is automatically segmented every 30 seconds
3. Segments are sent for transcription in real-time
4. Tap pause to stop recording

### Viewing Sessions
1. Browse recorded sessions in the main list
2. Tap a session to view detailed segments
3. Use search to find specific transcriptions
4. Filter by date range or transcription status

### Settings
- Configure recording quality (sample rate, bit depth)
- Set segmentation interval (default: 30 seconds)
- Manage API credentials
- View app statistics and storage usage

## 🧪 Testing

### Running Unit Tests
```bash
# Run all tests
xcodebuild test -scheme TwinMindAssignment -destination 'platform=iOS Simulator,name=iPhone 15'

# Run specific test file
xcodebuild test -scheme TwinMindAssignment -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:TwinMindAssignmentTests/AudioManagerTests
```

### Running UI Tests
```bash
xcodebuild test -scheme TwinMindAssignment -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:TwinMindAssignmentUITests
```

### Test Coverage
- Unit tests for audio recording and transcription logic
- Integration tests for API communication
- UI tests for critical user flows
- Performance tests for large datasets

## 🔧 Configuration

### Audio Settings
Modify `AudioManager.swift` to adjust:
- Sample rate (default: 44.1 kHz)
- Bit depth (default: 16-bit)
- Audio format (default: PCM)
- Segmentation interval (default: 30 seconds)

### Transcription Settings
Configure in `TranscriptionService.swift`:
- API endpoint URL
- Request timeout (default: 30 seconds)
- Retry attempts (default: 3)
- Fallback threshold (default: 5 consecutive failures)

### Storage Settings
Adjust in `AudioFileManager.swift`:
- Maximum storage usage
- Cleanup policies
- File compression settings

## 🐛 Known Issues & Limitations

### Current Limitations
1. **Background Recording**: Limited to 30 seconds without background app refresh
2. **Storage Management**: Manual cleanup required for large datasets
3. **Transcription Languages**: Currently optimized for English
4. **Network Handling**: Limited offline transcription capabilities

### Planned Improvements
- [ ] Enhanced background recording duration
- [ ] Automatic storage cleanup policies
- [ ] Multi-language transcription support
- [ ] Advanced audio processing (noise reduction)
- [ ] Export functionality for sessions
- [ ] iOS Widget support




## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙋‍♂️ Support

For questions, issues, or contributions, please:
1. Check existing issues on GitHub
2. Create a new issue with detailed description
3. Include device information and iOS version
4. Provide steps to reproduce any bugs

## 📚 Additional Resources

- [AVAudioEngine Documentation](https://developer.apple.com/documentation/avfaudio/avaudioengine)
- [SwiftData Documentation](https://developer.apple.com/documentation/swiftdata)
- [OpenAI Whisper API](https://platform.openai.com/docs/guides/speech-to-text)
- [iOS Audio Session Programming Guide](https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/Introduction/Introduction.html)

---
