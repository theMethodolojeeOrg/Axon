//
//  AudioPlayerDelegateWrapper.swift
//  Axon
//
//  Helper delegate for AVAudioPlayer completion callbacks
//

import AVFoundation

/// Wrapper for AVAudioPlayerDelegate to provide Swift closure-based callbacks
class AudioPlayerDelegateWrapper: NSObject, AVAudioPlayerDelegate {
    let completion: () -> Void

    init(completion: @escaping () -> Void) {
        self.completion = completion
        super.init()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        completion()
    }
}
