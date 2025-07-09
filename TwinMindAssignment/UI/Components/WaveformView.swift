//
//  WaveformView.swift
//  AudioApp
//
//

import SwiftUI

/// A view that renders a simple waveform based on an array of normalized audio samples.
/// Each sample is a Float between 0.0 and 1.0, representing the relative amplitude.
struct WaveformView: View {
    /// The normalized audio samples to plot (0.0 = silence, 1.0 = max amplitude).
    let samples: [Float]
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let centerY = h / 2
            
            // Calculate bar width with some spacing
            let barWidth = w / CGFloat(samples.count)
            let barSpacing: CGFloat = 1 // Small gap between bars
            let actualBarWidth = max(barWidth - barSpacing, 1)
            
            HStack(spacing: barSpacing) {
                ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                    // Convert sample to bar height (minimum height for visibility)
                    let barHeight = max(CGFloat(sample) * centerY, 2)
                    
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: actualBarWidth, height: barHeight)
                        .position(x: actualBarWidth / 2, y: centerY)
                }
            }
        }
    }
}

struct SiriLikeVisualizer: View {
    let samples: [Float]
    let layers: Int = 3
    
    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            
            ZStack {
                ForEach(0..<layers, id: \.self) { layer in
                    let layerOpacity = 1.0 - (Double(layer) * 0.3)
                    let layerScale = 1.0 - (Double(layer) * 0.2)
                    let baseRadius = (size / 6) * layerScale
                    
                    CircularWaveLayer(
                        samples: samples,
                        center: center,
                        baseRadius: baseRadius,
                        color: Color.blue.opacity(layerOpacity),
                        phase: Double(layer) * 0.2
                    )
                }
            }
        }
    }
}

struct CircularWaveLayer: View {
    let samples: [Float]
    let center: CGPoint
    let baseRadius: CGFloat
    let color: Color
    let phase: Double
    
    var body: some View {
        Path { path in
            guard !samples.isEmpty else { return }
            
            let angleStep = (2 * .pi) / Double(samples.count)
            
            for (i, sample) in samples.enumerated() {
                let angle = Double(i) * angleStep + phase - .pi / 2
                
                // More dynamic radius calculation
                let amplitude = CGFloat(sample) * baseRadius * 0.8
                let radius = baseRadius + amplitude * sin(angle * 2 + phase)
                
                let x = center.x + cos(angle) * radius
                let y = center.y + sin(angle) * radius
                
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            
            path.closeSubpath()
        }
        .stroke(color, lineWidth: 2)
        .animation(.easeInOut(duration: 0.1), value: samples)
    }
}

