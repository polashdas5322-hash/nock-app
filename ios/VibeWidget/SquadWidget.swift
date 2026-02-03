import WidgetKit
import SwiftUI

// MARK: - Squad Widget Entry
struct SquadEntry: TimelineEntry {
    let date: Date
    let recentVibes: [SquadVibeData]
}

// MARK: - Squad Vibe Data
struct SquadVibeData: Identifiable {
    let id: String
    let vibeId: String
    let senderName: String
    let senderId: String
    let imageURL: URL?
    let isPlayed: Bool
    let timestamp: Date
    let transcription: String?
}

// MARK: - Squad Timeline Provider
struct SquadTimelineProvider: TimelineProvider {
    typealias Entry = SquadEntry
    
    func placeholder(in context: Context) -> SquadEntry {
        SquadEntry(
            date: Date(),
            recentVibes: [
                SquadVibeData(id: "1", vibeId: "1", senderName: "Sarah", senderId: "s1", imageURL: nil, isPlayed: false, timestamp: Date(), transcription: nil),
                SquadVibeData(id: "2", vibeId: "2", senderName: "Alex", senderId: "s2", imageURL: nil, isPlayed: true, timestamp: Date(), transcription: nil),
                SquadVibeData(id: "3", vibeId: "3", senderName: "Mom", senderId: "s3", imageURL: nil, isPlayed: true, timestamp: Date(), transcription: nil)
            ]
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (SquadEntry) -> Void) {
        let entry = placeholder(in: context)
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<SquadEntry>) -> Void) {
        // Load vibes from App Group
        let vibes = loadVibesFromAppGroup()
        
        let entry = SquadEntry(
            date: Date(),
            recentVibes: vibes
        )
        
        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
    
    /// Load recent vibes from App Group shared data
    private func loadVibesFromAppGroup() -> [SquadVibeData] {
        guard let defaults = UserDefaults(suiteName: "group.com.nock.nock"),
              let data = defaults.data(forKey: "recent_vibes"),
              let vibesJson = try? JSONDecoder().decode([VibeJson].self, from: data) else {
            return []
        }
        
        // App group container URL for direct file access
        let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.nock.nock")
        
        return vibesJson.prefix(3).enumerated().map { index, vibe in
            // Use file-based access if possible to stay under 30MB Jetsam limit
            var imageURL: URL? = nil
            
            // The Flutter side (WidgetUpdateService.dart) saves images to the App Group container
            // using keys like "vibe_image_$vibeId"
            if let container = containerURL {
                 let fileURL = container.appendingPathComponent("vibe_image_\(vibe.vibeId)")
                 if FileManager.default.fileExists(atPath: fileURL.path) {
                     imageURL = fileURL
                 }
            }
            
            return SquadVibeData(
                id: "\(index)",
                vibeId: vibe.vibeId,
                senderName: vibe.senderName,
                senderId: vibe.senderId,
                imageURL: imageURL,
                isPlayed: vibe.isPlayed,
                timestamp: Date(timeIntervalSince1970: vibe.timestamp / 1000),
                transcription: vibe.transcription
            )
        }
    }
}

// MARK: - Vibe JSON (Codable)
struct VibeJson: Codable {
    let vibeId: String
    let senderName: String
    let senderId: String
    let imageUrl: String?
    let isPlayed: Bool
    let timestamp: Double
    let transcription: String?
}

// MARK: - Squad Widget View
struct SquadWidgetView: View {
    let entry: SquadEntry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                LinearGradient(
                    colors: [
                        Color(hex: "121226"),
                        Color(hex: "0A0A1A")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                if entry.recentVibes.isEmpty {
                    emptyStateView
                } else {
                    vibeGridView
                }
            }
        }
        .containerBackground(.clear, for: .widget)
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 32))
                .foregroundColor(.gray)
            
            Text("No vibes yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.gray)
            
            Text("Waiting for friends...")
                .font(.system(size: 11))
                .foregroundColor(.gray.opacity(0.7))
        }
    }
    
    // MARK: - Vibe Grid
    private var vibeGridView: some View {
        HStack(spacing: 12) {
            ForEach(entry.recentVibes) { vibe in
                vibeCard(vibe)
            }
        }
        .padding(.horizontal, 0)
        .padding(.vertical, 0)
    }
    
    // MARK: - Individual Vibe Card
    private func vibeCard(_ vibe: SquadVibeData) -> some View {
        Link(destination: URL(string: "nock://player/\(vibe.vibeId)")!) {
                // Image or Avatar
                ZStack {
                    let cardSize: CGFloat = 70
                    
                    if let imageURL = vibe.imageURL,
                       let uiImage = downsample(at: imageURL, to: CGSize(width: cardSize, height: cardSize)) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: cardSize, height: cardSize)
                            .clipShape(RoundedRectangle(cornerRadius: 28))
                    } else {
                        RoundedRectangle(cornerRadius: 28)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "D4F49C").opacity(0.3), Color(hex: "E5D1FA").opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: cardSize, height: cardSize)
                            .overlay(
                                Text(String(vibe.senderName.prefix(1)).uppercased())
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.white)
                            )
                    }
                    
                    // Unread indicator
                    if !vibe.isPlayed {
                        Circle()
                            .fill(Color(hex: "D4F49C"))
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle()
                                    .stroke(Color(hex: "121226"), lineWidth: 2)
                            )
                            .offset(x: cardSize/2 - 2, y: -cardSize/2 + 2)
                    }
                    
                    // Play button overlay
                    Circle()
                        .fill(Color.black.opacity(0.4))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                        )
                }
                
                // Sender name
                Text(vibe.senderName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                // Time ago
                Text(timeAgo(vibe.timestamp))
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
            }
        }
    }
    
    // MARK: - Time Formatting
    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d"
        }
    }
    
    // MARK: - Memory Efficient Downsampling (DISK BASED)
    private func downsample(at imageURL: URL, to pointSize: CGSize) -> UIImage? {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, imageSourceOptions) else {
            return nil
        }
        
        // Calculate max dimension (scale factor * point size)
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

// MARK: - Squad Widget
struct SquadWidget: Widget {
    let kind = "SquadWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: SquadTimelineProvider()
        ) { entry in
            SquadWidgetView(entry: entry)
        }
        .configurationDisplayName("Squad")
        .description("See your latest vibes at a glance")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Preview
#Preview(as: .systemMedium) {
    SquadWidget()
} timeline: {
    SquadEntry(
        date: .now,
        recentVibes: [
            SquadVibeData(id: "1", vibeId: "abc", senderName: "Sarah", senderId: "s1", imageURL: nil, isPlayed: false, timestamp: Date(), transcription: nil),
            SquadVibeData(id: "2", vibeId: "def", senderName: "Alex", senderId: "s2", imageURL: nil, isPlayed: true, timestamp: Date().addingTimeInterval(-3600), transcription: nil),
            SquadVibeData(id: "3", vibeId: "ghi", senderName: "Mom", senderId: "s3", imageURL: nil, isPlayed: true, timestamp: Date().addingTimeInterval(-86400), transcription: nil)
        ]
    )
}
