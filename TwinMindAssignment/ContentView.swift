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
    @Query private var items: [Item]
    @StateObject private var audioManager = AudioManager()
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Recording Tab
            NavigationView {
                VStack {
                    RecordingControlsView(audioManager: audioManager)
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
            NavigationView {
                List {
                    ForEach(items) { item in
                        NavigationLink {
                            Text("Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Recording Session")
                                    .font(.headline)
                                Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: deleteItems)
                }
                .navigationTitle("Sessions")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        EditButton()
                    }
                    ToolbarItem {
                        Button(action: addItem) {
                            Label("Add Item", systemImage: "plus")
                        }
                    }
                }
            }
            .tabItem {
                Image(systemName: "list.bullet")
                Text("Sessions")
            }
            .tag(1)
            
            // Settings Tab
            NavigationView {
                Form {
                    Section("Audio") {
                        HStack {
                            Image(systemName: "mic")
                            Text("Microphone Permission")
                            Spacer()
                            Image(systemName: audioManager.isPermissionGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(audioManager.isPermissionGranted ? .green : .red)
                        }
                        
                        HStack {
                            Image(systemName: "speaker.wave.2")
                            Text("Audio Route")
                            Spacer()
                            Text(audioManager.currentAudioRoute)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Background Recording")
                            Spacer()
                            Image(systemName: audioManager.isBackgroundRecordingSupported() ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(audioManager.isBackgroundRecordingSupported() ? .green : .orange)
                        }
                    }
                    
                    Section("Quality") {
                        HStack {
                            Image(systemName: "waveform")
                            Text("Recording Quality")
                            Spacer()
                            Text(audioManager.getConfigurationDisplayName(audioManager.audioConfiguration))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Section("Storage") {
                        HStack {
                            Image(systemName: "internaldrive")
                            Text("File Size")
                            Spacer()
                            Text(audioManager.getRecordingFileSize())
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if audioManager.isBackgroundRecordingEnabled {
                        Section("Background Status") {
                            HStack {
                                Image(systemName: "clock")
                                Text("Time Remaining")
                                Spacer()
                                Text(audioManager.formatDuration(audioManager.backgroundTimeRemaining))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.large)
            }
            .tabItem {
                Image(systemName: "gearshape")
                Text("Settings")
            }
            .tag(2)
        }
        .onAppear {
            // Request permissions on app launch if needed
            Task {
                await audioManager.checkPermissionStatus()
            }
        }
    }

    private func addItem() {
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
