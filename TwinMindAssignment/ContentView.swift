//
//  ContentView.swift
//  TwinMindAssignment
//
//  Created by Noor Bhatia on 08/07/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedTab = 0
    @EnvironmentObject private var errorHandler: ErrorManager
    
    var body: some View {
        TabView(selection: $selectedTab) {
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
        .errorAlert(errorHandler){
            
        }
       
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Session.self, inMemory: true)
}
