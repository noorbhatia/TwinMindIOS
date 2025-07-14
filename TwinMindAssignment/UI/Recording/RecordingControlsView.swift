import SwiftUI
import Speech
import SwiftData
import Foundation



struct RecordingView: View {
    @Environment(\.modelContext) private var modelContext

    @EnvironmentObject private var audioManager: AudioManager
    @EnvironmentObject private var errorManager: ErrorManager
    @EnvironmentObject private var localTranscriptionService: LocalTranscriptionService
    
    @State private var showingTitleInputAlert = false
    @State private var completedSession: Session?
    @State private var titleInputText = ""
    
    var body: some View {
        ZStack(alignment: .bottom) {
            if !showingTitleInputAlert {
                // Expandable Recording Container
                ZStack(alignment: .bottom) {
                    Rectangle()
                        .clipShape(.rect(cornerRadius: 12))
                        .ignoresSafeArea(edges: .bottom)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: audioManager.recordingState == .recording ? nil : 100)
                    
                    VStack() {
                        // Waveform - appears when recording
                        if audioManager.recordingState == .recording {
//                            Spacer()
                            
                            LiveWaveformView()
                                .frame(maxWidth: .infinity)
                                .frame(height: 300)
                                .animation(.easeOut, value: audioManager.recordingState)

                            
                        }
                        
                        // Record Button - always at bottom
                        RecordButton(state: audioManager.recordingState) {
                            toggleRecording()
                        } stopAction: {
                            stopRecordingAndShowTitleInput()
                        }
                        .frame(width: 70, height: 70)

                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: audioManager.recordingState)
                .animation(.easeInOut(duration: 0.3), value: showingTitleInputAlert)
            }
        }
        

        
        .alert("Recording Complete", isPresented: $showingTitleInputAlert) {
            TextField("Session Title", text: $titleInputText)
            Button("Cancel") {
                showingTitleInputAlert = false
                completedSession = nil
            }
            Button("Save") {
                saveTitleFromAlert()
            }
        } message: {
            if let session = completedSession {
                Text("Duration: \(session.formattedDuration)\nEnter a title for this recording session.")
            }
        }
        .onReceive(localTranscriptionService.$permissionStatus){status in
            if status == .denied || status == .restricted {
                 errorManager.reportError(.transcription(.speechRecognitionPermissionDenied), context: .init(component: "Speech", operation: "recognition"))
            }
        }
        .onAppear {
            Task{
                await audioManager.requestMicrophonePermission()
                await localTranscriptionService.requestSpeechRecognitionPermission()
            }
        }
    }
}

extension RecordingView{
    private func toggleRecording() {
        Task {
            if !localTranscriptionService.isAvailable || localTranscriptionService.permissionStatus != .authorized {
                errorManager.reportError(.transcription(.speechRecognitionPermissionDenied), context: .init(component: "Speech", operation: "recognition"))
                _ = await localTranscriptionService.requestSpeechRecognitionPermission()
                return
                
            }else{
                switch audioManager.recordingState {
                case .stopped:
                    await audioManager.startRecording()
                    break
                case .recording:
                    audioManager.pauseRecording()
                    break
                case .paused:
                    audioManager.resumeRecording()
                    break
                case .error(let string):
                    break
                }
                    
            }
            
        }
    }
    
    private func cancelRecording() {
        audioManager.cancelRecording()
    }
    
    private func stopRecordingAndShowTitleInput() {
        _ = audioManager.stopRecording()
        
        // Get the most recently completed session
//        Task {
//            if let session = getMostRecentCompletedSession() {
//                await MainActor.run {
//                    completedSession = session
//                    titleInputText = session.title
//                    showingTitleInputAlert = true
//                }
//            }
//        }
    }
    
    private func saveTitleFromAlert() {
        guard let session = completedSession else { return }
        
        let trimmedTitle = titleInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            session.updateTitle(trimmedTitle)
            do {
                try modelContext.save()
            } catch {
                print("Failed to save session title: \(error)")
            }
        }
        
        showingTitleInputAlert = false
        completedSession = nil
    }
    
    private func getMostRecentCompletedSession() -> Session? {
        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate<Session> { session in
                session.isCompleted == true
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        
        do {
            let sessions = try modelContext.fetch(descriptor)
            return sessions.first
        } catch {
            print("Failed to fetch recent session: \(error)")
            return nil
        }
    }
}


// MARK: - Record Button

struct RecordButton: View {
    let state: RecordingState
    let buttonColor: Color
    let borderColor: Color
    let animation: Animation
    let startAction: () -> Void
    let stopAction: () -> Void
    
    init(
        state: RecordingState,
        buttonColor: Color = .red,
        borderColor: Color = .white,
        animation: Animation = .easeInOut(duration: 0.25),
        startAction: @escaping () -> Void,
        stopAction: @escaping () -> Void
    ) {
        self.state = state
        self.buttonColor = buttonColor
        self.borderColor = borderColor
        self.animation = animation
        self.startAction = startAction
        self.stopAction = stopAction
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                let minDimension = min(geometry.size.width, geometry.size.height)
                
                Button {
                    switch state {
                    case .stopped:
                        startAction()
                    case .recording:
                        stopAction()
                    case .paused:
                        break
                    case .error(let string):
                        break
                    }
                    
                } label: {
                    RecordButtonShape(isRecording: state == .recording)
                        .fill(buttonColor)
                        .animation(animation, value: state == .recording)
                }
                
                Circle()
                    .strokeBorder(lineWidth: minDimension * 0.05)
                    .foregroundColor(borderColor)
            }
        }
    }
}
struct RecordButtonShape: Shape {
    var shapeRadius: CGFloat
    var distanceFromCardinal: CGFloat
    // `b` and `c` come from here: https://spencermortensen.com/articles/bezier-circle/
    var b: CGFloat
    var c: CGFloat
    
    init(isRecording: Bool) {
        self.shapeRadius = isRecording ? 1.0 : 0.0
        self.distanceFromCardinal = isRecording ? 1.0 : 0.0
        self.b = isRecording ? 0.90 : 0.553
        self.c = isRecording ? 1.00 : 0.999
    }
    
    var animatableData: AnimatablePair<Double, AnimatablePair<Double, AnimatablePair<Double, Double>>> {
        get {
            AnimatablePair(Double(shapeRadius),
                           AnimatablePair(Double(distanceFromCardinal),
                                          AnimatablePair(Double(b), Double(c))))
        }
        set {
            shapeRadius = Double(newValue.first)
            distanceFromCardinal = Double(newValue.second.first)
            b = Double(newValue.second.second.first)
            c = Double(newValue.second.second.second)
        }
    }
    
    func path(in rect: CGRect) -> Path {
        let minDimension = min(rect.maxX, rect.maxY)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = (minDimension / 2 * 0.82) - (shapeRadius * minDimension * 0.22)
        let movementFactor = 0.65
        
        let rightTop = CGPoint(x: center.x + radius, y: center.y - radius * movementFactor * distanceFromCardinal)
        let rightBottom = CGPoint(x: center.x + radius, y: center.y + radius * movementFactor * distanceFromCardinal)
        
        let topRight = CGPoint(x: center.x + radius * movementFactor * distanceFromCardinal, y: center.y - radius)
        let topLeft = CGPoint(x: center.x - radius * movementFactor * distanceFromCardinal, y: center.y - radius)
        
        let leftTop = CGPoint(x: center.x - radius, y: center.y - radius * movementFactor * distanceFromCardinal)
        let leftBottom = CGPoint(x: center.x - radius, y: center.y + radius * movementFactor * distanceFromCardinal)
        
        let bottomRight = CGPoint(x: center.x + radius * movementFactor * distanceFromCardinal, y: center.y + radius)
        let bottomLeft = CGPoint(x: center.x - radius * movementFactor * distanceFromCardinal, y: center.y + radius)
        
        let topRightControl1 = CGPoint(x: center.x + radius * c, y: center.y - radius * b)
        let topRightControl2 = CGPoint(x: center.x + radius * b, y: center.y - radius * c)
        
        let topLeftControl1 = CGPoint(x: center.x - radius * b, y: center.y - radius * c)
        let topLeftControl2 = CGPoint(x: center.x - radius * c, y: center.y - radius * b)
        
        let bottomLeftControl1 = CGPoint(x: center.x - radius * c, y: center.y + radius * b)
        let bottomLeftControl2 = CGPoint(x: center.x - radius * b, y: center.y + radius * c)
        
        let bottomRightControl1 = CGPoint(x: center.x + radius * b, y: center.y + radius * c)
        let bottomRightControl2 = CGPoint(x: center.x + radius * c, y: center.y + radius * b)
    
        var path = Path()
        
        path.move(to: rightTop)
        path.addCurve(to: topRight, control1: topRightControl1, control2: topRightControl2)
        path.addLine(to: topLeft)
        path.addCurve(to: leftTop, control1: topLeftControl1, control2: topLeftControl2)
        path.addLine(to: leftBottom)
        path.addCurve(to: bottomLeft, control1: bottomLeftControl1, control2: bottomLeftControl2)
        path.addLine(to: bottomRight)
        path.addCurve(to: rightBottom, control1: bottomRightControl1, control2: bottomRightControl2)
        path.addLine(to: rightTop)

        return path
    }
}



