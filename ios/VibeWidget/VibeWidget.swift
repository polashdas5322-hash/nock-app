import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Widget Data Model
struct VibeData: Codable {
    let senderName: String
    let senderId: String  // For nudge feature
    let audioUrl: String
    let imageUrl: String
    let videoUrl: String?  // 🎬 4-State Protocol: Video URL for deep linking
    let vibeId: String
    let timestamp: Date
    let isPlayed: Bool
    let audioDuration: Int
    let distance: String?  // Distance badge (73 requests)
    
    // 🎬 4-State Widget Protocol: Content type flags
    let isVideo: Bool       // True = Video vibe (show play overlay)
    let isAudioOnly: Bool   // True = Voice note only (show mic icon)
    
    /// 📝 Transcription-First: First 50 chars of voice message for glanceability
    /// Lets users read vibes in meetings/class without playing audio
    let transcription: String?
    
    // Non-codable: Local URL to downsampled image for reliability and 0-RAM timeline caching
    var localImageURL: URL?
    
    enum CodingKeys: String, CodingKey {
        case senderName, senderId, audioUrl, imageUrl, videoUrl, vibeId, timestamp, isPlayed, audioDuration, distance, isVideo, isAudioOnly, transcription, localImageURL
    }
    
    // CRITICAL FIX: Custom decoder to handle FCM timestamp as String
    // FCM data payloads ALWAYS send values as Strings, even numbers.
    // The default JSONDecoder with .millisecondsSince1970 expects a Number, 
    // causing silent decode failures that left the widget stale.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        senderName = try container.decode(String.self, forKey: .senderName)
        senderId = try container.decodeIfPresent(String.self, forKey: .senderId) ?? ""
        audioUrl = try container.decode(String.self, forKey: .audioUrl)
        imageUrl = try container.decode(String.self, forKey: .imageUrl)
        videoUrl = try container.decodeIfPresent(String.self, forKey: .videoUrl)
        vibeId = try container.decode(String.self, forKey: .vibeId)
        isPlayed = try container.decodeIfPresent(Bool.self, forKey: .isPlayed) ?? false
        audioDuration = try container.decodeIfPresent(Int.self, forKey: .audioDuration) ?? 0
        
        // 🎬 4-State Widget Protocol: Decode content type flags
        isVideo = try container.decodeIfPresent(Bool.self, forKey: .isVideo) ?? false
        isAudioOnly = try container.decodeIfPresent(Bool.self, forKey: .isAudioOnly) ?? false
        distance = try container.decodeIfPresent(String.self, forKey: .distance)
        transcription = try container.decodeIfPresent(String.self, forKey: .transcription)
        
        // Handle timestamp as String (FCM always sends strings)
        // Convert "1702382400000" -> Date
        if let timestampString = try container.decodeIfPresent(String.self, forKey: .timestamp),
           let timestampMillis = Double(timestampString) {
            timestamp = Date(timeIntervalSince1970: timestampMillis / 1000)
        } else if let timestampMillis = try container.decodeIfPresent(Double.self, forKey: .timestamp) {
            // Fallback: Handle if already a number (e.g., from UserDefaults)
            timestamp = Date(timeIntervalSince1970: timestampMillis / 1000)
        } else {
            timestamp = Date()
        }
        
        // Decode localImageURL if present (persisted after timeline generation)
        self.localImageURL = try container.decodeIfPresent(URL.self, forKey: .localImageURL)
    }
    
    // Custom encoder to ensure localImageURL is persisted
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(senderName, forKey: .senderName)
        try container.encode(senderId, forKey: .senderId)
        try container.encode(audioUrl, forKey: .audioUrl)
        try container.encode(imageUrl, forKey: .imageUrl)
        try container.encode(videoUrl, forKey: .videoUrl)
        try container.encode(vibeId, forKey: .vibeId)
        try container.encode(isPlayed, forKey: .isPlayed)
        try container.encode(audioDuration, forKey: .audioDuration)
        try container.encode(isVideo, forKey: .isVideo)
        try container.encode(isAudioOnly, forKey: .isAudioOnly)
        try container.encode(distance, forKey: .distance)
        try container.encode(transcription, forKey: .transcription)
        
        // Encode Date as Double for compatibility with Flutter-to-Native bridge expectations
        try container.encode(timestamp.timeIntervalSince1970 * 1000, forKey: .timestamp)
        
        try container.encode(localImageURL, forKey: .localImageURL)
    }
    
    // Standard memberwise init for creating placeholder/manual instances
    init(senderName: String, senderId: String, audioUrl: String, imageUrl: String, 
         videoUrl: String? = nil, vibeId: String, timestamp: Date, isPlayed: Bool, 
         audioDuration: Int, distance: String?, isVideo: Bool = false, 
         isAudioOnly: Bool = false, transcription: String?, localImageURL: URL?) {
        self.senderName = senderName
        self.senderId = senderId
        self.audioUrl = audioUrl
        self.imageUrl = imageUrl
        self.videoUrl = videoUrl
        self.vibeId = vibeId
        self.timestamp = timestamp
        self.isPlayed = isPlayed
        self.audioDuration = audioDuration
        self.distance = distance
        self.isVideo = isVideo
        self.isAudioOnly = isAudioOnly
        self.transcription = transcription
        self.localImageURL = localImageURL
    }
    
    static let placeholder = VibeData(
        senderName: "Vibe",
        senderId: "",
        audioUrl: "",
        imageUrl: "",
        videoUrl: nil,
        vibeId: "",
        timestamp: Date(),
        isPlayed: true,
        audioDuration: 0,
        distance: nil,
        isVideo: false,
        isAudioOnly: false,
        transcription: nil,
        localImageURL: nil
    )
}

// MARK: - Widget Entry
struct VibeEntry: TimelineEntry {
    let date: Date
    let vibeData: VibeData?
    let configuration: ConfigurationAppIntent
}

// MARK: - Configuration Intent
struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Vibe Widget"
    static var description = IntentDescription("Shows your latest Vibe")
}

// MARK: - Timeline Provider
struct VibeTimelineProvider: AppIntentTimelineProvider {
    typealias Entry = VibeEntry
    typealias Intent = ConfigurationAppIntent

    func placeholder(in context: Context) -> VibeEntry {
        VibeEntry(date: Date(), vibeData: VibeData.placeholder, configuration: ConfigurationAppIntent())
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> VibeEntry {
        var vibeData = await loadVibeData()
        // CRITICAL FIX: Pre-download image for snapshot reliability
        if let data = vibeData, !data.imageUrl.isEmpty {
            vibeData = await downloadImageData(for: data)
        }
        return VibeEntry(date: Date(), vibeData: vibeData, configuration: configuration)
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<VibeEntry> {
        var vibeData = await loadVibeData()
        // CRITICAL FIX: Pre-download image in timeline provider
        // This prevents blank widgets when AsyncImage times out
        if let data = vibeData, !data.imageUrl.isEmpty {
            vibeData = await downloadImageData(for: data)
        }
        
        let entry = VibeEntry(date: Date(), vibeData: vibeData, configuration: configuration)
        
        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
    
    private func loadVibeData() async -> VibeData? {
        // Load from shared UserDefaults with App Group
        let sharedDefaults = UserDefaults(suiteName: "group.com.nock.nock")
        
        guard let jsonString = sharedDefaults?.string(forKey: "vibeData"),
              let data = jsonString.data(using: .utf8) else {
            return nil
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try? decoder.decode(VibeData.self, from: data)
    }
    
    /// CRITICAL FIX: Memory-safe image download for widgets
    /// 
    /// iOS Widget extensions have strict limits:
    /// - ~30MB memory limit
    /// - Few seconds execution time
    /// 
    /// This implementation:
    /// 1. Uses ephemeral session with strict 5-second timeout
    /// 2. Downloads directly to disk (URLSession.download) to avoid RAM spikes
    /// 3. Downsamples large images using CGImageSource (memory-safe streaming)
    /// 4. Always returns gracefully (never hangs)
    private func downloadImageData(for vibeData: VibeData) async -> VibeData {
        guard let url = URL(string: vibeData.imageUrl) else { return vibeData }
        
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5.0
        config.timeoutIntervalForResource = 5.0
        let session = URLSession(configuration: config)
        
        do {
            // STEP 1: Download directly to a temporary file on disk. 
            let (tempURL, _) = try await session.download(from: url)
            
            // STEP 2: Downsample and save to App Group container for persistence across reloads
            let localURL = try saveDownsampledImage(at: tempURL, for: vibeData.vibeId)
            
            var updatedData = vibeData
            updatedData.localImageURL = localURL
            return updatedData
        } catch {
            print("VibeWidget: Failed to download image: \(error.localizedDescription)")
            return vibeData
        }
    }
    
    /// Downsamples image from a temp URL and saves it to the App Group container
    private func saveDownsampledImage(at url: URL, for vibeId: String) throws -> URL? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceThumbnailMaxPixelSize: 500
        ]
        
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        
        // Save to App Group container so the widget view can access it even after provider finishes
        let fileManager = FileManager.default
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.com.nock.nock") else {
            return nil
        }
        
        let destinationURL = containerURL.appendingPathComponent("vibe_thumb_\(vibeId).jpg")
        
        // Convert to JPEG and save
        let uiImage = UIImage(cgImage: cgImage)
        if let data = uiImage.jpegData(compressionQuality: 0.8) {
            try data.write(to: destinationURL)
            return destinationURL
        }
        
        return nil
    }
}



// MARK: - Widget View
struct VibeWidgetEntryView: View {
    var entry: VibeTimelineProvider.Entry
    @Environment(\.widgetFamily) var family
    // iOS 18+ Tinted Mode Support
    @Environment(\.widgetRenderingMode) var renderingMode

    var body: some View {
        // LOCK SCREEN WIDGET: Compact circular/rectangular view for iOS 16+ Lock Screen
        switch family {
        case .accessoryCircular:
            accessoryCircularView
        case .accessoryRectangular:
            accessoryRectangularView
        case .accessoryInline:
            accessoryInlineView
        default:
            // Home Screen widgets (.systemSmall, .systemMedium)
            homeScreenView
        }
    }
    
    // MARK: - Lock Screen: Circular Widget (iOS 16+)
    private var accessoryCircularView: some View {
        ZStack {
            // Show "NEW" indicator or sender initial
            if let vibeData = entry.vibeData {
                if !vibeData.isPlayed {
                    // New vibe - show pulsing indicator
                    AccessoryWidgetBackground()
                    VStack(spacing: 2) {
                        Image(systemName: "waveform")
                            .font(.system(size: 16, weight: .bold))
                        Text("NEW")
                            .font(.system(size: 8, weight: .bold))
                    }
                } else {
                    // Played - show sender initial
                    AccessoryWidgetBackground()
                    Text(String(vibeData.senderName.prefix(1)).uppercased())
                        .font(.system(size: 24, weight: .bold))
                }
            } else {
                // No vibe - show app icon
                AccessoryWidgetBackground()
                Image(systemName: "hand.wave.fill")
                    .font(.system(size: 20))
            }
        }
    }
    
    // MARK: - Lock Screen: Rectangular Widget (iOS 16+)
    private var accessoryRectangularView: some View {
        HStack(spacing: 8) {
            // Left: Sender initial in circle
            ZStack {
                Circle()
                    .fill(.white.opacity(0.2))
                    .frame(width: 36, height: 36)
                Text(String((entry.vibeData?.senderName ?? "N").prefix(1)).uppercased())
                    .font(.system(size: 16, weight: .bold))
            }
            
            // Right: Sender name + status
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if let vibeData = entry.vibeData, !vibeData.isPlayed {
                        Circle()
                            .fill(Color(hex: "D4F49C"))
                            .frame(width: 6, height: 6)
                    }
                    Text(entry.vibeData?.senderName ?? "Nock")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                }
                
                if let transcription = entry.vibeData?.transcription, !transcription.isEmpty {
                    Text(transcription)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .privacySensitive()
                } else if let duration = entry.vibeData?.audioDuration, duration > 0 {
                    Text("\(duration)s voice note")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
    }
    
    // MARK: - Lock Screen: Inline Widget (iOS 16+)
    private var accessoryInlineView: some View {
        HStack(spacing: 4) {
            if let vibeData = entry.vibeData {
                if !vibeData.isPlayed {
                    Image(systemName: "waveform")
                }
                Text(vibeData.senderName)
                if let duration = vibeData.audioDuration, duration > 0 {
                    Text("• \(duration)s")
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "hand.wave.fill")
                Text("Nock")
            }
        }
    }
    // MARK: - Home Screen Widget View
    private var homeScreenView: some View {
        // Main Container
        ZStack {
            // Background Layer
            if let vibeData = entry.vibeData, let uiImage = UIImage(contentsOfFile: vibeData.localImageURL?.path ?? "") {
                // Check if we are in "Tinted" / "Accented" mode (iOS 18+)
                if #available(iOS 18.0, *), renderingMode == .accented {
                    // TINTED MODE: Hide full color photo, show abstract or simplified view
                    // Photos look bad when desaturated by the OS tint filter.
                    // Instead, we show a clean container that takes the system tint.
                    ContainerRelativeShape()
                        .fill(Color(hex: "121226").opacity(0.3))
                } else {
                    // STANDARD MODE: Show full bleed photo
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .overlay(
                            LinearGradient(
                                gradient: Gradient(colors: [.black.opacity(0.6), .clear, .black.opacity(0.8)]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            } else {
                // Fallback / No Data
                gradientBackground
            }
            
            // 🎬 4-State Widget Protocol: Content Type Overlays
            if let vibeData = entry.vibeData {
                if vibeData.isVideo {
                    // VIDEO: Large centered play button with dark overlay
                    Color.black.opacity(0.3)
                    VStack {
                        Spacer()
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.white.opacity(0.9))
                            .shadow(radius: 8)
                        Text("Video")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.top, 4)
                        Spacer()
                    }
                } else if vibeData.isAudioOnly {
                    // AUDIO ONLY: Mic icon in center (avatar is background)
                    VStack {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.15))
                                .frame(width: 60, height: 60)
                            Image(systemName: "mic.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                        }
                        Text("\(vibeData.audioDuration)s voice note")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.top, 8)
                        Spacer()
                    }
                }
                // IMAGE + AUDIO / IMAGE ONLY: No center overlay (showing the photo)
            }
            
            // Distance Badge - Top left corner
            if let vibeData = entry.vibeData,
               let distance = vibeData.distance,
               !distance.isEmpty {
                VStack {
                    HStack {
                        Text("📍 \(distance)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(hex: "121226").opacity(0.6))
                            .cornerRadius(8)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(8)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 8) {
                Spacer()
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        // New indicator
                        if let vibeData = entry.vibeData, !vibeData.isPlayed {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color(hex: "D4F49C"))
                                    .frame(width: 8, height: 8)
                                Text("NEW")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(hex: "D4F49C"))
                            }
                        }
                        
                        // Sender name
                        Text(entry.vibeData?.senderName ?? "Vibe")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        
                        // Transcription or duration info
                        // 🎬 4-State Protocol: Different labels per content type
                        if let vibeData = entry.vibeData {
                            if let transcription = vibeData.transcription, !transcription.isEmpty {
                                Text("\"\(transcription)\"")
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundColor(.white.opacity(0.9))
                                    .lineLimit(2)
                                    .italic()
                                    .privacySensitive()
                            } else if vibeData.isVideo {
                                Text("📹 Video • \(vibeData.audioDuration)s")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.8))
                            } else if vibeData.isAudioOnly {
                                Text("🎤 Voice note • \(vibeData.audioDuration)s")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.8))
                            } else if vibeData.audioDuration > 0 {
                                Text("📷 Photo • \(vibeData.audioDuration)s audio")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.8))
                            } else {
                                Text("📷 Photo")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        // Play button
                        // CRITICAL FIX: Only show if there is audio/video to play
                        // "Image Only" vibes should not show a play button.
                        if let vibeData = entry.vibeData, !vibeData.audioUrl.isEmpty {
                            playButton
                        }
                        
                        // Reply button (Walkie-Talkie)
                        // CRITICAL: Aligned with Research Recommendation 10.1
                        // Opens app directly into Recording Mode for this friend
                        if entry.vibeData != nil {
                            replyButton
                        }
                    }
                }
            }
            .padding(0)
        }
        .containerBackground(for: .widget) {
            gradientBackground
        }
    }
    
    private var gradientBackground: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(hex: "121226"),
                Color(hex: "0A0A1A")
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    @ViewBuilder
    private var playButton: some View {
        if #available(iOS 17.0, *) {
            // CRITICAL FIX: Use PlayVibeIntent (AudioPlaybackIntent protocol)
            // Grants iOS background audio entitlement needed to keep process alive.
            Button(intent: PlayVibeIntent(
                audioUrl: entry.vibeData?.audioUrl ?? "",
                senderName: entry.vibeData?.senderName ?? "Vibe",
                vibeId: entry.vibeData?.vibeId ?? ""
            )) {
                playButtonContent
            }
            .buttonStyle(.plain)
        } else {
            // Pre-iOS 17: Link opens the app
            Link(destination: URL(string: "nock://player/\(entry.vibeData?.vibeId ?? "")")!) {
                playButtonContent
            }
        }
    }
    
    private var playButtonContent: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "D4F49C").opacity(0.15))
                .frame(width: 44, height: 44)
            
            Circle()
                .stroke(Color(hex: "D4F49C").opacity(0.8), lineWidth: 1.5)
                .frame(width: 44, height: 44)
            
            Image(systemName: "play.fill")
                .font(.system(size: 16))
                .foregroundColor(Color(hex: "D4F49C"))
        }
    }
    
    @ViewBuilder
    private var replyButton: some View {
        // Use RecordVibeIntent which deep links to nock://record?to=friendId
        Button(intent: RecordVibeIntent(friendId: entry.vibeData?.senderId ?? "")) {
            ZStack {
                Circle()
                    .fill(Color(hex: "E5D1FA").opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Circle()
                    .stroke(Color(hex: "E5D1FA").opacity(0.8), lineWidth: 1.5)
                    .frame(width: 44, height: 44)
                
                Image(systemName: "mic.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Color(hex: "E5D1FA"))
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Widget Definition
struct VibeWidget: Widget {
    let kind: String = "VibeWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: ConfigurationAppIntent.self,
            provider: VibeTimelineProvider()
        ) { entry in
            VibeWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Vibe")
        .description("See your latest voice messages")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Memory Efficient Downsampling
extension View {
    func downsample(imageData: Data, to pointSize: CGSize) -> UIImage? {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, imageSourceOptions) else {
            return nil
        }
        
        let scale = UIScreen.main.scale
        let maxDimensionInPixels = max(pointSize.width, pointSize.height) * scale
        
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimensionInPixels
        ] as CFDictionary
        
        guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
            return nil
        }
        
        return UIImage(cgImage: downsampledImage)
    }
}

// MARK: - Preview
#Preview(as: .systemSmall) {
    VibeWidget()
} timeline: {
    VibeEntry(
        date: .now,
        vibeData: VibeData(
            senderName: "Sarah",
            audioUrl: "https://example.com/audio.m4a",
            imageUrl: "",
            vibeId: "123",
            timestamp: Date(),
            isPlayed: false,
            audioDuration: 5
        ),
        configuration: ConfigurationAppIntent()
    )
    VibeEntry(
        date: .now,
        vibeData: nil,
        configuration: ConfigurationAppIntent()
    )
}
