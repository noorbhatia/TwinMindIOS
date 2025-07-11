import SwiftUI
import SwiftData
import AVFoundation

struct SessionDetailView: View {
    @Bindable var session: Session
    @ObservedObject var player: AudioPlayer
    
    
    @State private var showingDeleteAlert = false
    @State private var showingShareSheet = false
    @State private var shareText = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Session Header
                    sessionHeaderView
                    
                    // Audio Waveform
//                    audioWaveformView
                    
                    // Session Metadata
                    sessionMetadataView
                    
                    // Transcription Overview
                    transcriptionOverviewView
                    
                    // Segments List
                    if !session.segments.isEmpty {
                        segmentsListView
                    }
                    
                    
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .navigationTitle("Session Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
        Button(role: .destructive, action: { showingDeleteAlert = true }) {
                            Label("Delete Session", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .alert("Delete Session", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                deleteSession()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this recording session? This action cannot be undone.")
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(text: shareText)
        }
    }
    
    private var sessionHeaderView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(session.title)
                .font(.largeTitle)
                .fontWeight(.bold)
            
            HStack {
                Label(session.formattedDuration, systemImage: "clock")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if session.isCompleted {
                    Label("Completed", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundColor(.green)
                } else {
                    Label("In Progress", systemImage: "clock")
                        .font(.headline)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var audioWaveformView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Audio Waveform")
                .font(.headline)
            
            if let fileURL = session.fileURL, session.isCompleted {
                SimpleStaticWaveformView(audioURL: fileURL)
                    .frame(height: 80)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    
                    Text("Waveform will be available when recording is complete")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(height: 80)
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var sessionMetadataView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recording Details")
                .font(.headline)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                MetadataItemView(title: "Start Time", value: session.startTime.formatted(.dateTime))
                MetadataItemView(title: "Duration", value: session.formattedDuration)
                MetadataItemView(title: "File Size", value: session.formattedFileSize)
                MetadataItemView(title: "Quality", value: session.audioQuality)
                MetadataItemView(title: "Sample Rate", value: "\(Int(session.sampleRate)) Hz")
                MetadataItemView(title: "Channels", value: "\(session.channels)")
                
                if session.wasInterrupted {
                    MetadataItemView(title: "Status", value: "Interrupted", isWarning: true)
                }
                
                if session.backgroundRecordingUsed {
                    MetadataItemView(title: "Background", value: "Used", isInfo: true)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var transcriptionOverviewView: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Transcription")
                    .font(.title2)
                    .bold()
                
                Spacer()
                
                if !session.segments.isEmpty {
                    Text("\(session.completedTranscriptionsCount)/\(session.totalTranscriptionsCount) segments")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 6)
            
            if session.segments.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "waveform.circle")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text("No segments available")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
 
                if !session.fullTranscriptionText.isEmpty {
                    
                    Text(session.fullTranscriptionText)
                        .font(.body)
                    
                    
                } else {
                    Text("Transcription pending...")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .italic()
                }
                
            }
        }
    }
    
    private var segmentsListView: some View {
        VStack(alignment: .leading) {
            Text("Audio Segments")
                .font(.title2)
                .bold()
                .padding(.bottom, 6)
            
            LazyVStack(spacing: 12) {
                ForEach(session.segments.sorted { $0.segmentIndex < $1.segmentIndex }) { segment in
                    SegmentRowView(segment: segment)
                }
            }
        }
        .padding(.top, 12)
    }
    
    
    
    
    private func deleteSession() {
        dismiss()
    }
}


struct MetadataItemView: View {
    let title: String
    let value: String
    var isWarning: Bool = false
    var isInfo: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(isWarning ? .orange : isInfo ? .blue : .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SegmentRowView: View {
    let segment: AudioSegment
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Segment \(segment.segmentIndex + 1)")
                    .font(.headline)
                
                if let transcription = segment.transcription, !transcription.text.isEmpty {
                    Text(transcription.text)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .padding(.top, 4)
                }
            }
            
            Spacer()
            
            if segment.failureCount > 0 {
                Button(action: retrySegment) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(.rect(cornerRadius: 8))
       
    }
    
    private var transcriptionStatusBadge: some View {
        Group {
            if let transcription = segment.transcription {
                if transcription.isCompleted {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Label("Processing", systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            } else if segment.isProcessed {
                Label("Failed", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.red)
            } else if segment.failureCount > 0 {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else {
                Label("Pending", systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func retrySegment() {
        // This would trigger a retry for this specific segment
        // Implementation would depend on how we expose the transcription service
    }
}

struct StaticWaveformDisplayView: View {
    let audioURL: URL
    @State private var waveformSamples: [Float] = []
    @State private var isLoading = true
    @State private var loadingError: String?
    
    var body: some View {
        Group {
            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Generating waveform...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 80)
                .background(Color(.systemBackground))
                .cornerRadius(8)
            } else if let error = loadingError {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.badge.exclamationmark")
                        .foregroundColor(.secondary)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 80)
                .background(Color(.systemBackground))
                .cornerRadius(8)
            } else {
                Canvas { context, size in
                    drawWaveform(context: context, size: size)
                }
                .frame(height: 80)
                .background(Color(.systemBackground))
                .cornerRadius(8)
            }
        }
        .task {
            await generateWaveform()
        }
    }
    
    private func drawWaveform(context: GraphicsContext, size: CGSize) {
        guard !waveformSamples.isEmpty else { return }
        
        let width = size.width
        let height = size.height
        let midY = height / 2
        
        // Calculate bar width and spacing
        let totalBars = min(waveformSamples.count, Int(width / 1.5))
        let barWidth: CGFloat = max(1, (width / CGFloat(totalBars)) * 0.8)
        let spacing: CGFloat = (width / CGFloat(totalBars)) * 0.2
        
        var path = Path()
        
        for (index, sample) in waveformSamples.enumerated() {
            guard index < totalBars else { break }
            
            let x = CGFloat(index) * (barWidth + spacing)
            let normalizedSample = max(0.02, min(1.0, sample))
            let barHeight = CGFloat(normalizedSample) * (height * 0.9)
            
            let rect = CGRect(
                x: x,
                y: midY - barHeight / 2,
                width: barWidth,
                height: barHeight
            )
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2))
        }
        
        context.fill(path, with: .color(.blue))
    }
    
    private func generateWaveform() async {
        do {
            let samples = try await WaveformAnalyzer.generateWaveform(from: audioURL, targetSamples: 100)
            await MainActor.run {
                self.waveformSamples = samples
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.loadingError = "Could not generate waveform"
                self.isLoading = false
            }
        }
    }
}

// MARK: - Waveform Analyzer

actor WaveformAnalyzer {
    static func generateWaveform(from url: URL, targetSamples: Int = 100) async throws -> [Float] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let asset = AVAsset(url: url)
                    guard let track = asset.tracks(withMediaType: .audio).first else {
                        throw WaveformError.noAudioTrack
                    }
                    
                    let reader = try AVAssetReader(asset: asset)
                    let outputSettings: [String: Any] = [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsBigEndianKey: false,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsNonInterleaved: false
                    ]
                    
                    let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
                    reader.add(output)
                    reader.startReading()
                    
                    var samples: [Float] = []
                    
                    while reader.status == .reading {
                        if let sampleBuffer = output.copyNextSampleBuffer() {
                            if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                                let length = CMBlockBufferGetDataLength(blockBuffer)
                                var data = Data(count: length)
                                
                                data.withUnsafeMutableBytes { bytes in
                                    CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: bytes.baseAddress!)
                                }
                                
                                // Convert to samples and downsample
                                let audioSamples = data.withUnsafeBytes { bytes in
                                    Array(bytes.bindMemory(to: Int16.self))
                                }
                                
                                // Convert to normalized float values and downsample
                                let downsampleFactor = max(1, audioSamples.count / targetSamples)
                                for i in stride(from: 0, to: audioSamples.count, by: downsampleFactor) {
                                    let sample = Float(audioSamples[i]) / Float(Int16.max)
                                    samples.append(abs(sample))
                                }
                            }
                        }
                    }
                    
                    // Ensure we have the target number of samples
                    let finalSamples = Array(samples.prefix(targetSamples))
                    continuation.resume(returning: finalSamples)
                    
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    enum WaveformError: LocalizedError {
        case noAudioTrack
        case processingFailed
        
        var errorDescription: String? {
            switch self {
            case .noAudioTrack:
                return "No audio track found in the file"
            case .processingFailed:
                return "Failed to process audio file"
            }
        }
    }
}

struct SimpleStaticWaveformView: View {
    let audioURL: URL
    @State private var waveformSamples: [Float] = []
    @State private var isLoading = true
    @State private var loadingError: String?
    
    var body: some View {
        Group {
            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Generating waveform...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 80)
                .background(Color(.systemBackground))
                .cornerRadius(8)
            } else if let error = loadingError {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.badge.exclamationmark")
                        .foregroundColor(.secondary)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 80)
                .background(Color(.systemBackground))
                .cornerRadius(8)
            } else {
                Canvas { context, size in
                    drawWaveform(context: context, size: size)
                }
                .frame(height: 80)
                .background(Color(.systemBackground))
                .cornerRadius(8)
            }
        }
        .task {
            await generateWaveform()
        }
    }
    
    private func drawWaveform(context: GraphicsContext, size: CGSize) {
        guard !waveformSamples.isEmpty else { return }
        
        let width = size.width
        let height = size.height
        let midY = height / 2
        
        let totalBars = min(waveformSamples.count, Int(width / 1.5))
        let barWidth: CGFloat = max(1, (width / CGFloat(totalBars)) * 0.8)
        let spacing: CGFloat = (width / CGFloat(totalBars)) * 0.2
        
        var path = Path()
        
        for (index, sample) in waveformSamples.enumerated() {
            guard index < totalBars else { break }
            
            let x = CGFloat(index) * (barWidth + spacing)
            let normalizedSample = max(0.02, min(1.0, sample))
            let barHeight = CGFloat(normalizedSample) * height * 0.9
            
            let rect = CGRect(
                x: x,
                y: midY - barHeight / 2,
                width: barWidth,
                height: barHeight
            )
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2))
        }
        
        context.fill(path, with: .color(.blue))
    }
    
    private func generateWaveform() async {
        do {
            let samples = try await generateWaveformSamples(from: audioURL, targetSamples: 100)
            await MainActor.run {
                self.waveformSamples = samples
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.loadingError = "Could not generate waveform"
                self.isLoading = false
            }
        }
    }
    
    private func generateWaveformSamples(from url: URL, targetSamples: Int) async throws -> [Float] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let asset = AVAsset(url: url)
                    guard let track = asset.tracks(withMediaType: .audio).first else {
                        continuation.resume(throwing: NSError(domain: "WaveformError", code: 1, userInfo: [NSLocalizedDescriptionKey: "No audio track found"]))
                        return
                    }
                    
                    let reader = try AVAssetReader(asset: asset)
                    let outputSettings: [String: Any] = [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsBigEndianKey: false,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsNonInterleaved: false
                    ]
                    
                    let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
                    reader.add(output)
                    reader.startReading()
                    
                    var samples: [Float] = []
                    
                    while reader.status == .reading {
                        if let sampleBuffer = output.copyNextSampleBuffer() {
                            if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                                let length = CMBlockBufferGetDataLength(blockBuffer)
                                var data = Data(count: length)
                                
                                data.withUnsafeMutableBytes { bytes in
                                    CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: bytes.baseAddress!)
                                }
                                
                                let audioSamples = data.withUnsafeBytes { bytes in
                                    Array(bytes.bindMemory(to: Int16.self))
                                }
                                
                                let downsampleFactor = max(1, audioSamples.count / targetSamples)
                                for i in stride(from: 0, to: audioSamples.count, by: downsampleFactor) {
                                    let sample = Float(audioSamples[i]) / Float(Int16.max)
                                    samples.append(abs(sample))
                                }
                            }
                        }
                    }
                    
                    let finalSamples = Array(samples.prefix(targetSamples))
                    continuation.resume(returning: finalSamples)
                    
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let text: String
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let activityViewController = UIActivityViewController(
            activityItems: [text],
            applicationActivities: nil
        )
        return activityViewController
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
} 
