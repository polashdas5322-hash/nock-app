import AVFoundation
import MediaPlayer

/// AudioManager - Robust audio engine for widget background playback
/// This is a standalone singleton that can be used across the widget extension
/// Provides proper background audio, now playing info, and remote control support
@available(iOS 14.0, *)
class AudioManager: NSObject, ObservableObject {
    static let shared = AudioManager()
    
    private var audioPlayer: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0.0
    @Published var duration: Double = 0.0
    @Published var progress: Double = 0.0
    
    // Current audio info
    private var currentSenderName: String = ""
    private var currentVibeId: String = ""
    
    private override init() {
        super.init()
        setupAudioSession()
        setupRemoteCommandCenter()
    }
    
    deinit {
        removeTimeObserver()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Audio Session Setup
    
    /// Configure audio session for background playback
    /// CRITICAL: Must use .playback category to continue when screen locks
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            
            // .playback category: Audio continues when screen locks or app backgrounds
            // .spokenAudio mode: Optimized for voice messages, ducks other audio
            // This is REQUIRED for background audio - without it, iOS silences on lock
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.allowAirPlay, .allowBluetooth, .allowBluetoothA2DP]
            )
            
            // NOTE: Do NOT activate here. We only activate in play()
            // to minimize background resource usage and privacy indicators.
            
            // Listen for interruptions (phone calls, etc.)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleInterruption),
                name: AVAudioSession.interruptionNotification,
                object: session
            )
            
            // Listen for route changes (headphones plugged/unplugged)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleRouteChange),
                name: AVAudioSession.routeChangeNotification,
                object: session
            )
            
            print("AudioManager: Audio session configured for background playback (.playback category)")
        } catch {
            print("AudioManager: Failed to setup audio session: \(error.localizedDescription)")
        }
    }
    
    /// Re-activate audio session before playback (important for widgets)
    private func ensureAudioSessionActive() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("AudioManager: Failed to activate session: \(error.localizedDescription)")
        }
    }
    
    /// Handle audio interruptions (phone calls, Siri, etc.)
    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            // Interruption began - pause playback
            pause()
            print("AudioManager: Playback interrupted")
            
        case .ended:
            // Interruption ended - resume if appropriate
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    resume()
                    print("AudioManager: Resuming after interruption")
                }
            }
            
        @unknown default:
            break
        }
    }
    
    /// Handle route changes (headphones, Bluetooth, etc.)
    @objc private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        // Pause when headphones are unplugged (standard iOS behavior)
        if reason == .oldDeviceUnavailable {
            pause()
            print("AudioManager: Audio route changed - paused")
        }
    }
    
    // MARK: - Remote Command Center (Lock Screen Controls)
    
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            if self?.isPlaying == true {
                self?.pause()
            } else {
                self?.resume()
            }
            return .success
        }
    }
    
    // MARK: - Playback Methods
    
    func play(url: URL, senderName: String = "Vibe", vibeId: String = "") {
        // Store current info
        currentSenderName = senderName
        currentVibeId = vibeId
        
        // Stop any existing playback
        stop()
        
        // CRITICAL: Re-activate audio session before playback
        // This ensures background audio works from widget
        ensureAudioSessionActive()
        
        // Create new player item
        playerItem = AVPlayerItem(url: url)
        audioPlayer = AVPlayer(playerItem: playerItem)
        
        // Add completion observer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
        
        // Add time observer
        addTimeObserver()
        
        // Start playback
        audioPlayer?.play()
        isPlaying = true
        
        // Update now playing info
        updateNowPlayingInfo()
    }
    
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }
    
    func resume() {
        audioPlayer?.play()
        isPlaying = true
        updateNowPlayingInfo()
    }
    
    func stop() {
        removeTimeObserver()
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
        
        audioPlayer?.pause()
        audioPlayer = nil
        playerItem = nil
        isPlaying = false
        currentTime = 0.0
        progress = 0.0
        
        // Clear now playing info
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        
        // CRITICAL PRIVACY FIX: Deactivate session when stopping
        // This removes the "Orange Dot" or background audio entry immediately
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                print("AudioManager: Audio session deactivated via stop()")
            } catch {
                print("AudioManager: Failed to deactivate: \(error)")
            }
        }
    }
    
    // MARK: - Time Observer
    
    private func addTimeObserver() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = audioPlayer?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, let item = self.playerItem else { return }
            
            self.currentTime = time.seconds
            self.duration = item.duration.seconds
            
            if self.duration > 0 && !self.duration.isNaN {
                self.progress = self.currentTime / self.duration
            }
        }
    }
    
    private func removeTimeObserver() {
        if let observer = timeObserver {
            audioPlayer?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }
    
    // MARK: - Now Playing Info (Lock Screen)
    
    private func updateNowPlayingInfo() {
        var info = [String: Any]()
        
        info[MPMediaItemPropertyTitle] = "Voice Message"
        info[MPMediaItemPropertyArtist] = currentSenderName
        info[MPMediaItemPropertyAlbumTitle] = "Vibe"
        
        if let item = playerItem {
            let duration = item.duration.seconds
            if !duration.isNaN {
                info[MPMediaItemPropertyPlaybackDuration] = duration
            }
        }
        
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    // MARK: - Callbacks
    
    @objc private func playerDidFinishPlaying(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.isPlaying = false
            self?.progress = 0.0
            self?.currentTime = 0.0
            
            // Clear now playing info
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            
            // CRITICAL PRIVACY FIX: Deactivate session after playback finishes
            // This ensures the widget doesn't leave an active session entry
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                print("AudioManager: Audio session deactivated after playback finished")
            } catch {
                print("AudioManager: Failed to deactivate after finish: \(error)")
            }
        }
    }
}

// MARK: - Async Play Method (For AppIntents)

@available(iOS 17.0, *)
extension AudioManager {
    /// Async play method for use with AppIntents
    func playAsync(url: URL, senderName: String = "Vibe", vibeId: String = "") async {
        await MainActor.run {
            play(url: url, senderName: senderName, vibeId: vibeId)
        }
    }
}
