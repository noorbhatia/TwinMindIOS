//
//  AudioPlayer.swift
//  TwinMindAssignment
//
//  Created by Noor Bhatia on 09/07/25.
//

import AVFoundation

final class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var queue: [URL] = []
    
    
    func play(urls: [URL]) {
        stop()
        queue = urls
        playNext()
    }
    
    func stop() {
        player?.stop()
        player = nil
        queue.removeAll()
    }
    
    
    private func playNext() {
        guard !queue.isEmpty else { return }
        let url = queue.removeFirst()
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            p.play()
            player = p
        } catch {
            print("AudioPlayer failed to play \(url):", error)
            // skip to next if this one errors
            playNext()
        }
    }
    
    
}
