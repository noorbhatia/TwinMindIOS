//
//  WaveformView.swift
//  AudioApp
//
//

import SwiftUI
import SwiftData

struct LiveWaveformView: View {
    @EnvironmentObject private var audioManager: AudioManager
    
    let barWidth: CGFloat = 4
    let barSpacing: CGFloat = 2
    let maxBarHeight: CGFloat = 100
    let numberOfBars: Int = 60
    
    @State private var barHeights: [CGFloat] = []
    @State private var animationTimer: Timer?
    @State private var scrollOffset: CGFloat = 0
    @State private var smoothedAudioLevel: Float = 0.0
    @State private var lastUpdateTime: Date = Date()
    private let updateInterval: TimeInterval = 0.1 // Update every 100ms
    
    var body: some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(0..<numberOfBars, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(colorForBar(at: index))
                    .frame(width: barWidth, height: getBarHeight(at: index))
                    .opacity(getBarOpacity(at: index))
            }
        }
        .frame(height: maxBarHeight)
        .frame(maxWidth: .infinity)
        .offset(x: scrollOffset)
        .animation(.easeInOut(duration: 0.3), value: barHeights)
        .animation(.easeInOut(duration: 0.2), value: scrollOffset)
        .onAppear {
            setupInitialHeights()
        }
        .onReceive(audioManager.$isRecording) { isRecording in
            if isRecording {
                startAnimation()
            } else {
                stopAnimation()
            }
        }
        .onReceive(audioManager.$audioLevel) { level in
            updateWaveform(with: level)
        }
        .onReceive(audioManager.$currentRecordingDuration) { duration in
            updateScrollPosition(duration: duration)
        }
    }
    
    private func setupInitialHeights() {
        barHeights = Array(repeating: 2.0, count: numberOfBars)
        scrollOffset = 0
        smoothedAudioLevel = 0.0
        lastUpdateTime = Date()
    }
    

    
    private func getBarHeight(at index: Int) -> CGFloat {
        guard index < barHeights.count else { return 2.0 }
        return max(barHeights[index], 2.0)
    }
    
    private func colorForBar(at index: Int) -> Color {
        let progress = Double(index) / Double(numberOfBars - 1)
        let height = getBarHeight(at: index)
        let intensity = min(height / maxBarHeight, 1.0)
        
        // Create gradient from red to green
        let hue = progress * 0.33 // 0 = red, 0.33 = green
        let saturation = 0.8 + intensity * 0.2
        let brightness = 0.6 + intensity * 0.4
        
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }
    
    private func updateWaveform(with audioLevel: Float) {
        guard audioManager.isRecording else { return }
        
        // Throttle updates to prevent vibrating effect
        let currentTime = Date()
        guard currentTime.timeIntervalSince(lastUpdateTime) >= updateInterval else { return }
        lastUpdateTime = currentTime
        
        // Convert dB to normalized amplitude (0-1)
        let normalizedLevel = convertDbToAmplitude(audioLevel)
        
        // Apply smoothing to reduce vibrating effect
        let smoothingFactor: Float = 0.3
        smoothedAudioLevel = smoothedAudioLevel * (1 - smoothingFactor) + normalizedLevel * smoothingFactor
        
        // Add new bar to the right side (shift existing bars left)
        let newBarHeight = generateSingleBarHeight(from: smoothedAudioLevel)
        
        // Shift existing bars to the left and add new bar on the right
        if barHeights.count >= numberOfBars {
            barHeights.removeFirst()
        }
        barHeights.append(newBarHeight)
        
        // Ensure we have the right number of bars
        while barHeights.count < numberOfBars {
            barHeights.insert(2.0, at: 0)
        }
    }
    
    private func convertDbToAmplitude(_ db: Float) -> Float {
        // Convert dB to amplitude (0-1) for live visualization
        let clampedDb = max(-60, min(0, db))
        let normalized = (clampedDb + 60) / 60
        
        // Apply slight curve for better visual response
        return pow(normalized, 0.7)
    }
    

    
    private func startAnimation() {
        // No artificial animation - pure live audio visualization
        // Animation happens only from actual audio level updates
    }
    
    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        
        // Fade out animation and reset all state
        withAnimation(.easeOut(duration: 0.5)) {
            barHeights = Array(repeating: 2.0, count: numberOfBars)
            scrollOffset = 0
        }
        
        // Reset smoothing state
        smoothedAudioLevel = 0.0
        lastUpdateTime = Date()
    }
    
    private func getBarOpacity(at index: Int) -> Double {
        // Fade out older bars (left side) for timeline effect
        let progress = Double(index) / Double(numberOfBars - 1)
        return 0.3 + (progress * 0.7) // Fade from 30% to 100% opacity
    }
    
    private func updateScrollPosition(duration: TimeInterval) {
        // Subtle scrolling effect based on recording duration
        let scrollSpeed: CGFloat = 0.2
        let targetOffset = -CGFloat(duration) * scrollSpeed
        
        // Smooth interpolation to reduce jittering
        scrollOffset = scrollOffset * 0.9 + targetOffset * 0.1
    }
    
    private func generateSingleBarHeight(from amplitude: Float) -> CGFloat {
        // Pure audio level visualization - no randomness
        let baseHeight = amplitude * Float(maxBarHeight)
        
        return CGFloat(max(baseHeight, 2.0))
    }
}

// MARK: - Preview
struct LiveWaveformView_Previews: PreviewProvider {
    static var previews: some View {
        LiveWaveformView()
            .background(Color.black)
    }
}



