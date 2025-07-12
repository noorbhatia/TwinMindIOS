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


