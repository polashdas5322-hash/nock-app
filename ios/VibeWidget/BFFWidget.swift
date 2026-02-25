import WidgetKit
import SwiftUI
import AppIntents

// MARK: - BFF Widget Entry
struct BFFEntry: TimelineEntry {
    let date: Date
    let friendId: String
    let friendName: String
    let avatarURL: URL?
    let streak: Int
    let lastVibeTime: Date?
}

// MARK: - BFF Timeline Provider
struct BFFTimelineProvider: AppIntentTimelineProvider {
    typealias Entry = BFFEntry
    typealias Intent = SelectFriendIntent
    
    func placeholder(in context: Context) -> BFFEntry {
        BFFEntry(
            date: Date(),
            friendId: "placeholder",
            friendName: "BFF",
            avatarURL: nil,
            streak: 0,
            lastVibeTime: nil
        )
    }
    
    func snapshot(for configuration: SelectFriendIntent, in context: Context) async -> BFFEntry {
        let friend = configuration.friend
        return BFFEntry(
            date: Date(),
            friendId: friend?.id ?? "demo",
            friendName: friend?.name ?? "Best Friend",
            avatarURL: nil,
            streak: 7,
            lastVibeTime: Date()
        )
    }
    
    func timeline(for configuration: SelectFriendIntent, in context: Context) async -> Timeline<BFFEntry> {
        let friend = configuration.friend
        
        // App group container URL for direct file access (Prevents Jetsam 30MB crash)
        let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.nock.nock")
        
        var avatarURL: URL? = nil
        var streak = 0
        
        if let friendId = friend?.id,
           let defaults = UserDefaults(suiteName: "group.com.nock.nock") {
            // Read metadata
            streak = defaults.integer(forKey: "streak_\(friendId)")
            
            // Construct file URL for the cached avatar (saved by WidgetUpdateService.dart)
            if let container = containerURL {
                let fileURL = container.appendingPathComponent("avatar_\(friendId)")
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    avatarURL = fileURL
                }
            }
        }
        
        let entry = BFFEntry(
            date: Date(),
            friendId: friend?.id ?? "",
            friendName: friend?.name ?? "Select Friend",
            avatarURL: avatarURL,
            streak: streak,
            lastVibeTime: nil
        )
        
        // Refresh every hour
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
}

// MARK: - BFF Widget View
struct BFFWidgetView: View {
    let entry: BFFEntry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .accessoryCircular:
            accessoryCircularView
        case .systemMedium:
            mediumView
        default:
            homeScreenView
        }
    }
    
    // MARK: - Medium View (Wide)
    private var mediumView: some View {
        Button(intent: RecordVibeIntent(friendId: entry.friendId)) {
            GeometryReader { geometry in
                ZStack {
                    // Background gradient
                    LinearGradient(
                        colors: [
                            Color(hex: "121226"),
                            Color(hex: "0A0A1A")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    HStack(spacing: 16) {
                        // Avatar (Left Side)
                        ZStack {
                            let size = geometry.size.height * 0.7
                            
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "D4F49C"), Color(hex: "E5D1FA")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: size, height: size)
                            
                            if let imageURL = entry.avatarURL,
                               let uiImage = downsample(at: imageURL, to: CGSize(width: size, height: size)) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: size * 0.9, height: size * 0.9)
                                    .clipShape(Circle())
                            } else {
                                Text(String(entry.friendName.prefix(1)).uppercased())
                                    .font(.system(size: size * 0.4, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            
                            // Mic indicator
                            Circle()
                                .fill(Color(hex: "D4F49C"))
                                .frame(width: size * 0.3, height: size * 0.3)
                                .overlay(
                                    Image(systemName: "mic.fill")
                                        .font(.system(size: size * 0.15))
                                        .foregroundColor(.black)
                                )
                                .offset(x: size * 0.35, y: size * 0.35)
                        }
                        
                        // Details (Right Side)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.friendName)
                                .font(.system(size: 18, weight: .bold)) // Larger text
                                .foregroundColor(.white)
                                .lineLimit(1)
                            
                            if entry.streak > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "flame.fill")
                                        .foregroundColor(.orange)
                                    Text("\(entry.streak) day streak")
                                        .foregroundColor(.white)
                                }
                                .font(.system(size: 14, weight: .medium))
                            } else {
                                Text("Send a vibe")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                }
            }
            .containerBackground(.clear, for: .widget)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Lock Screen Circular View
    private var accessoryCircularView: some View {
        Button(intent: RecordVibeIntent(friendId: entry.friendId)) {
            ZStack {
                AccessoryWidgetBackground()
                
                VStack(spacing: 2) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 20))
                        .widgetAccentable()
                    
                    Text(String(entry.friendName.prefix(3)))
                        .font(.system(size: 8, weight: .medium))
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Home Screen Small View
    private var homeScreenView: some View {
        Button(intent: RecordVibeIntent(friendId: entry.friendId)) {
            GeometryReader { geometry in
                ZStack {
                    // Background gradient
                    LinearGradient(
                        colors: [
                            Color(hex: "121226"),
                            Color(hex: "0A0A1A")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    VStack(spacing: 8) {
                        // Avatar
                        ZStack {
                            let avatarSize = geometry.size.width * 0.45
                            let imageSize = avatarSize * 0.9
                            
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "D4F49C"), Color(hex: "E5D1FA")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: avatarSize, height: avatarSize)
                            
                            if let imageURL = entry.avatarURL,
                               let uiImage = downsample(at: imageURL, to: CGSize(width: imageSize, height: imageSize)) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: imageSize, height: imageSize)
                                    .clipShape(Circle())
                            } else {
                                Text(String(entry.friendName.prefix(1)).uppercased())
                                    .font(.system(size: avatarSize * 0.4, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            
                            // Mic indicator
                            Circle()
                                .fill(Color(hex: "D4F49C"))
                                .frame(width: avatarSize * 0.3, height: avatarSize * 0.3)
                                .overlay(
                                    Image(systemName: "mic.fill")
                                        .font(.system(size: avatarSize * 0.15))
                                        .foregroundColor(.black)
                                )
                                .offset(x: avatarSize * 0.35, y: avatarSize * 0.35)
                        }
                        
                        // Name
                        Text(entry.friendName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        // Streak (if any)
                        if entry.streak > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "flame.fill")
                                    .foregroundColor(.orange)
                                Text("\(entry.streak)")
                                    .foregroundColor(.white)
                            }
                            .font(.system(size: 12, weight: .medium))
                        } else {
                            Text("Tap to record")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .containerBackground(.clear, for: .widget)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Memory Efficient Downsampling (DISK BASED)
    private func downsample(at imageURL: URL, to pointSize: CGSize) -> UIImage? {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, imageSourceOptions) else {
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

// MARK: - BFF Widget
struct BFFWidget: Widget {
    let kind = "BFFWidget"
    
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectFriendIntent.self,
            provider: BFFTimelineProvider()
        ) { entry in
            BFFWidgetView(entry: entry)
        }
        .configurationDisplayName("BFF")
        .description("Quick access to your closest friend")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

// MARK: - Preview
#Preview(as: .systemSmall) {
    BFFWidget()
} timeline: {
    BFFEntry(
        date: .now,
        friendId: "123",
        friendName: "Sarah",
        avatarURL: nil,
        streak: 32,
        lastVibeTime: Date()
    )
}
