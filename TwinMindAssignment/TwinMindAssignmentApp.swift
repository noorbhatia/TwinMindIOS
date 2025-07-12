//
//  TwinMindAssignmentApp.swift
//  TwinMindAssignment
//
//  Created by Noor Bhatia on 08/07/25.
//

import SwiftUI
import SwiftData
import Speech

@main
struct TwinMindAssignmentApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Session.self,
            AudioSegment.self,
            Transcription.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(sharedModelContainer)
        }
    }
}

// MARK: - Service Initialization View
struct ServiceInitializationView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var errorHandler = ErrorManager()
    @State private var audioManager: AudioManager?
    @State private var segmentationService: AudioSegmentationService?
    @State private var transcriptionService: TranscriptionService?
    @State private var localTranscriptionService: LocalTranscriptionService?
    @State private var servicesInitialized = false
    
    var body: some View {
        Group {
            if servicesInitialized,
               let audioManager = audioManager,
               let segmentationService = segmentationService,
               let transcriptionService = transcriptionService,
               let localTranscriptionService = localTranscriptionService {
                
                TabView {
                    // Recording Tab
                    NavigationView {
                        RecordingControlsView()
                    }
                    .tabItem {
                        Image(systemName: "mic.circle")
                        Text("Record")
                    }
                    .tag(0)
                    
                    // Sessions Tab
                    SessionListView()
                    .tabItem {
                        Image(systemName: "list.bullet")
                        Text("Sessions")
                    }
                    .tag(1)
                    
                    // Settings Tab
                    NavigationView {
                        SettingsView()
                    }
                    .tabItem {
                        Image(systemName: "gear")
                        Text("Settings")
                    }
                    .tag(2)
                }
                .environmentObject(errorHandler)
                .environmentObject(audioManager)
                .environmentObject(segmentationService)
                .environmentObject(transcriptionService)
                .environmentObject(localTranscriptionService)
                .errorAlert(errorHandler) {
                    
                }
                
            } else {
                ProgressView("Initializing...")
                    .onAppear {
                        initializeServices()
                    }
            }
        }
    }
    
    private func initializeServices() {
        guard !servicesInitialized else { return }
        let status = SFSpeechRecognizer.authorizationStatus()
        let localTranService =  LocalTranscriptionService(
            errorManager: errorHandler,
            status: status
        )
        localTranscriptionService = localTranService
        
        let transService = TranscriptionService(
            modelContext: modelContext,
            errorManager: errorHandler,
            localTranscriptionService: localTranService
        )
        transcriptionService = transService
        // Initialize services with proper model context
        audioManager = AudioManager(
            modelContext: modelContext,
            errorManager: errorHandler,
            transcriptionService: transService
            
        )
        segmentationService = AudioSegmentationService(
            modelContext: modelContext,
            errorManager: errorHandler
        )
        
        
        
        
        servicesInitialized = true
    }
}
