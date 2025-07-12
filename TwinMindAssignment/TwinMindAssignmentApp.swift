//
//  TwinMindAssignmentApp.swift
//  TwinMindAssignment
//
//  Created by Noor Bhatia on 08/07/25.
//

import SwiftUI
import SwiftData

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
    
    @StateObject private var errorHandler = ErrorManager()
    @State private var audioManager:AudioManager?
    @State private var segmentationService: AudioSegmentationService?
    @State private var transcriptionService: TranscriptionService?
    @State private var localTranscriptionService: LocalTranscriptionService?
    @Environment(\.modelContext) private var modelContext

    var body: some Scene {
        WindowGroup {
            Group{
                if let audioManager = audioManager, let segmentationService = segmentationService, let transcriptionService = transcriptionService,  let localTranscriptionService = localTranscriptionService{
                    
                    ContentView()
                        .environmentObject(errorHandler)
                        .environmentObject(audioManager)
                        .environmentObject(segmentationService)
                        .environmentObject(transcriptionService)
                        .environmentObject(localTranscriptionService)
                        .modelContainer(sharedModelContainer)
                    
                }else{
                    ProgressView("Initializing..")
                }
            }
            .onAppear {
                if audioManager == nil {
                    audioManager = AudioManager(
                        modelContext: modelContext,
                        errorManager: errorHandler
                    )
                }
                if segmentationService == nil {
                    segmentationService = AudioSegmentationService(
                        modelContext: modelContext,
                        errorManager: errorHandler
                    )
                }
                if transcriptionService == nil {
                    transcriptionService = TranscriptionService(
                        modelContext: modelContext,
                        errorManager: errorHandler
                    )
                }
                if localTranscriptionService == nil {
                    localTranscriptionService = LocalTranscriptionService(
                        errorManager: errorHandler
                    )
                }
            }
            
        }
        
    }
}
