import SwiftUI
import SwiftData

struct SessionListView: View {
    
    @EnvironmentObject private var segmentationService: AudioSegmentationService
    @EnvironmentObject private var transcriptionService: TranscriptionService
    @Query private var recordingSessions: [Session]

    @State private var searchText = ""
    @State private var selectedSession: Session?
    @State private var showingDeleteAlert = false
    @State private var sessionToDelete: Session?
    @StateObject var player = AudioPlayer()
    var filteredSessions: [Session] {
        if searchText.isEmpty {
            return recordingSessions.sorted { $0.startTime > $1.startTime }
        } else {
            return recordingSessions.filter { session in
                session.title.localizedCaseInsensitiveContains(searchText) ||
                session.fullTranscriptionText.localizedCaseInsensitiveContains(searchText)
            }.sorted { $0.startTime > $1.startTime }
        }
    }
    
    var groupedSessions: [(String, [Session])] {
        let grouped = Dictionary(grouping: filteredSessions) { session in
            DateFormatter.sessionGroupFormatter.string(from: session.startTime)
        }
        
        return grouped.sorted { $0.key > $1.key }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if recordingSessions.isEmpty {
                    emptyStateView
                } else {
                    sessionsList
                }
            }
            .navigationTitle("Recording Sessions")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search sessions or transcriptions")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
        }
        .onAppear(perform: {
            print("Query result: \(recordingSessions.count) sessions")

            
        })
        .sheet(item: $selectedSession) { session in
            SessionDetailView(

                session: session,
                player: player
            )
        }
        .alert("Delete Session", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let session = sessionToDelete {
                    deleteSession(session)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this recording session? This action cannot be undone.")
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Recordings Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Start recording to see your sessions here")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
    
    private var sessionsList: some View {
        List {
            ForEach(groupedSessions, id: \.0) { dateGroup, sessions in
                Section(header: Text(dateGroup)) {
                    ForEach(sessions) { session in
                        SessionRowView(
                            session: session,
                            onTap: {
                                selectedSession = session
                            },
                            onDelete: {
                                sessionToDelete = session
                                showingDeleteAlert = true
                            }
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    private func deleteSession(_ session: Session) {
        withAnimation {
            // Clean up associated files
            Task {
                await segmentationService.cleanupSegments(for: session)
            }
            
            // Delete from model context will be handled by the parent view
            // since we don't have direct access to modelContext here
        }
    }
}

struct SessionRowView: View {
    let session: Session
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    // Title and duration
                    HStack {
                        Text(session.title)
                            .font(.headline)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text(session.formattedDuration)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Time and status
                    HStack {
                        Text(session.startTime, format: .dateTime.hour().minute())
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if session.isCompleted {
                            transcriptionStatusView
                        } else {
                            Label("In Progress", systemImage: "clock")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    // File size and format
                    HStack {
                        Text(session.formattedFileSize)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(session.audioQuality)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    // Transcription preview
                    if !session.fullTranscriptionText.isEmpty {
                        Text(session.fullTranscriptionText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .padding(.top, 4)
                    }
                }
                .padding(.vertical, 4)
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onTap) {
                Label("View Details", systemImage: "eye")
            }
            
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private var transcriptionStatusView: some View {
        Group {
            if session.totalTranscriptionsCount == 0 {
                Label("Not Transcribed", systemImage: "text.bubble")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                let progress = session.transcriptionProgress
                if progress >= 1.0 {
                    Label("Transcribed", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else if progress > 0 {
                    Label("Transcribing...", systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.blue)
                } else {
                    Label("Pending", systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
    }
}

// MARK: - Extensions

extension DateFormatter {
    static let sessionGroupFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter
    }()
} 
