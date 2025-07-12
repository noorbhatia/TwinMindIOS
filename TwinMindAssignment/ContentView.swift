//
//  ContentView.swift
//  TwinMindAssignment
//
//  Created by Noor Bhatia on 08/07/25.
//

import SwiftUI
import SwiftData
import Speech

struct ContentView: View {
    var body: some View {
        ServiceInitializationView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Session.self, inMemory: true)
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
                
                SessionListView()
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
