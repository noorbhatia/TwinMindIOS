//
//  ContentView.swift
//  TwinMindAssignment
//
//  Created by Noor Bhatia on 08/07/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var recordingSessions: [Session]
    @State private var audioManager: AudioManager?
    @State private var segmentationService: AudioSegmentationService?
    @State private var transcriptionService: TranscriptionService?
    @State private var selectedTab = 0
    @StateObject private var errorHandler = ErrorManager()
    var body: some View {
        TabView(selection: $selectedTab) {
            // Recording Tab
            NavigationView {
                VStack {
                    if let audioManager = audioManager {
                        RecordingControlsView(audioManager: audioManager)
                    } else {
                        ProgressView("Initializing...")
                    }
                    Spacer()
                }
                .navigationTitle("Audio Recorder")
                .navigationBarTitleDisplayMode(.large)
            }
            .tabItem {
                Image(systemName: "mic.circle")
                Text("Record")
            }
            .tag(0)
            
            // Sessions Tab
            Group {
                if let segmentationService = segmentationService,
                   let transcriptionService = transcriptionService {
                    SessionListView(
                        sessions: recordingSessions,
                        segmentationService: segmentationService,
                        transcriptionService: transcriptionService
                    )
                } else {
                    NavigationView {
                        ProgressView("Loading...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .tabItem {
                Image(systemName: "list.bullet")
                Text("Sessions")
            }
            .tag(1)
            
            // Settings Tab
            Group {
                if let audioManager = audioManager,
                   let transcriptionService = transcriptionService {
                    NavigationView {
                        SettingsView(
                            audioManager: audioManager,
                            transcriptionService: transcriptionService
                        )
                    }
                } else {
                    NavigationView {
                        ProgressView("Loading...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .tabItem {
                Image(systemName: "gear")
                Text("Settings")
            }
            .tag(2)
        }
        .errorAlert(errorHandler){
            
        }
        .onAppear {
            // Initialize services with model context
            if audioManager == nil {
                audioManager = AudioManager(modelContext: modelContext, errorManager: errorHandler)
            }
            if segmentationService == nil {
                segmentationService = AudioSegmentationService(modelContext: modelContext, errorManager: errorHandler)
            }
            if transcriptionService == nil {
                transcriptionService = TranscriptionService(modelContext: modelContext, errorManager: errorHandler)
            }
            
            // Request permissions on app launch if needed
            if let audioManager = audioManager {
                Task {
                    await audioManager.checkPermissionStatus()
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Session.self, inMemory: true)
}
