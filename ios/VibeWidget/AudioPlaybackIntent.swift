import AVFoundation
import AppIntents
import WidgetKit
import SwiftUI

// MARK: - Audio Playback Intent (iOS 17+)
/// Enables playing audio directly from the widget without opening the app
/// 
/// CRITICAL: Uses AudioPlaybackIntent (iOS 17+) NOT AudioStartingIntent (deprecated)
/// AudioPlaybackIntent grants the system background audio entitlement needed to
/// keep the process alive while audio plays from the widget.
/// 
/// Apple Docs: "Adopt this protocol to indicate to the system that your App Intent 
/// plays audio. The system can then avoid dialogue or other experiences that 
/// might interrupt that audio."

@available(iOS 17.0, *)
struct VibeAudioPlaybackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Play Vibe Audio"
    static var description = IntentDescription("Plays voice message audio from the home screen widget")
    
    @Parameter(title: "Audio URL")
    var audioUrl: String
    
    @Parameter(title: "Sender Name")
    var senderName: String
    
    @Parameter(title: "Vibe ID")
    var vibeId: String
    
    init() {
        self.audioUrl = ""
        self.senderName = ""
        self.vibeId = ""
    }
    
    init(audioUrl: String, senderName: String, vibeId: String) {
        self.audioUrl = audioUrl
        self.senderName = senderName
        self.vibeId = vibeId
    }
    
    func perform() async throws -> some IntentResult {
        // CRITICAL FIX #1: Activate AVAudioSession IMMEDIATELY on native side
        // This MUST happen before any async work (like waiting for Flutter)
        // It signals to iOS that audio is about to start, buying time for initialization
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            print("VibeAudioPlaybackIntent: Audio session activated NATIVE side")
        } catch {
            print("VibeAudioPlaybackIntent: Failed to activate audio session: \(error)")
        }
        
        // Validate URL
        guard let url = URL(string: audioUrl), !audioUrl.isEmpty else {
            print("VibeAudioPlaybackIntent: Invalid audio URL")
            return .result()
        }
        
        // Get the audio manager and play
        // Now safe to do async work - iOS knows audio is coming
        let audioManager = AudioManager.shared
        await audioManager.playAsync(url: url, senderName: senderName, vibeId: vibeId)
        
        // Mark as played in shared UserDefaults
        let sharedDefaults = UserDefaults(suiteName: "group.com.nock.nock")
        sharedDefaults?.set(true, forKey: "isPlayed_\(vibeId)")
        sharedDefaults?.set(Date(), forKey: "playedAt_\(vibeId)")
        sharedDefaults?.synchronize()
        
        // Trigger widget refresh to update UI (remove "NEW" indicator)
        WidgetCenter.shared.reloadTimelines(ofKind: "VibeWidget")
        
        return .result()
    }
}

// MARK: - Stop Audio Intent

@available(iOS 17.0, *)
struct StopVibeAudioIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Vibe Audio"
    static var description = IntentDescription("Stops the currently playing voice message")
    
    init() {}
    
    func perform() async throws -> some IntentResult {
        await MainActor.run {
            AudioManager.shared.stop()
        }
        return .result()
    }
}

// MARK: - Widget Audio Playback Button

@available(iOS 17.0, *)
struct AudioPlaybackButton: View {
    let audioUrl: String
    let senderName: String
    let vibeId: String
    
    var body: some View {
        Button(intent: VibeAudioPlaybackIntent(
            audioUrl: audioUrl,
            senderName: senderName,
            vibeId: vibeId
        )) {
            ZStack {
                // Outer glow
                Circle()
                    .fill(Color(hex: "#00F0FF").opacity(0.2))
                    .frame(width: 48, height: 48)
                
                // Border
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color(hex: "#00F0FF"), Color(hex: "#00F0FF").opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 44, height: 44)
                
                // Play icon
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(hex: "#00F0FF"))
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stop Button

@available(iOS 17.0, *)
struct StopAudioButton: View {
    var body: some View {
        Button(intent: StopVibeAudioIntent()) {
            ZStack {
                Circle()
                    .fill(Color(hex: "#FF0099").opacity(0.2))
                    .frame(width: 48, height: 48)
                
                Circle()
                    .stroke(Color(hex: "#FF0099"), lineWidth: 2)
                    .frame(width: 44, height: 44)
                
                Image(systemName: "stop.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: "#FF0099"))
            }
        }
        .buttonStyle(.plain)
    }
}
