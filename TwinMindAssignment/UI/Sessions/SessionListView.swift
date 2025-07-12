import SwiftUI
import SwiftData

struct SessionListView: View {
    
    @EnvironmentObject private var segmentationService: AudioSegmentationService
    @EnvironmentObject private var transcriptionService: TranscriptionService
    @Environment(\.modelContext) private var modelContext
    @Query private var recordingSessions: [Session]

    @State private var searchText = ""
    @State private var selectedSession: Session?
    @State private var showingDeleteAlert = false
    @State private var sessionToDelete: Session?
    @State private var sessionsBeingDeleted: Set<UUID> = []
    @StateObject var player = AudioPlayer()
    
    
    //MARK: - Computed properties
    var filteredSessions: [Session] {
        let sessions = recordingSessions.filter { !sessionsBeingDeleted.contains($0.id) }
        
        if searchText.isEmpty {
            return sessions.sorted { $0.startTime > $1.startTime }
        } else {
            return sessions.filter { session in
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
                } else if filteredSessions.isEmpty {
                    // Show search results empty state
                    VStack(spacing: 20) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text("No Results Found")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Try adjusting your search terms")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding(40)
                } else {
                    sessionsList
                }
            }
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search sessions or transcriptions")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
        }
        
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
        List{
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
                    .onDelete { indexSet in
                        for index in indexSet {
                            sessionToDelete = sessions[index]
                            showingDeleteAlert = true
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    private func deleteSession(_ session: Session) {
        // First, mark the session as being deleted to trigger smooth animation
        withAnimation(.easeInOut(duration: 0.3)) {
            sessionsBeingDeleted.insert(session.id)
        }
        
        // After animation completes, actually delete the session
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            Task {
                await segmentationService.cleanupSegments(for: session)
            }
            
            modelContext.delete(session)
            do {
                try modelContext.save()
                // Remove from pending deletion set (cleanup)
                sessionsBeingDeleted.remove(session.id)
            } catch {
                // If deletion fails, restore the session in the UI
                withAnimation {
                    sessionsBeingDeleted.remove(session.id)
                }
                print("Failed to delete session: \(error.localizedDescription)")
            }
        }
    }
}
//MARK: - List Item View
struct SessionRowView: View {
    let session: Session
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Button(action: onTap) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(session.title)
                            .font(.headline)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text(session.formattedDuration)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    
                    HStack{
                            Text(session.startTime, format: .dateTime.hour().minute())
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()

                            Text(session.formattedFileSize)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                     
                    
                    // Transcription preview
                    if !session.fullTranscriptionText.isEmpty {
                        Text(session.fullTranscriptionText)
                            .font(.caption)
                            .italic()
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .padding(.top, 4)
                    }
                }
                .padding(.vertical, 4)
                
               
            
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
    
    
}

// MARK: - Extensions

extension DateFormatter {
    static let sessionGroupFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter
    }()
} 
