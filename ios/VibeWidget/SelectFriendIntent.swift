import AppIntents
import WidgetKit

// MARK: - Friend Entity for Widget Configuration
/// Represents a friend that can be selected for the BFF widget
struct FriendEntity: AppEntity {
    let id: String
    let name: String
    let avatarUrl: String?
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Friend"
    static var defaultQuery = FriendQuery()
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

// MARK: - Friend Query
/// Fetches friends from the shared App Group container
struct FriendQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [FriendEntity] {
        return loadFriendsFromAppGroup().filter { identifiers.contains($0.id) }
    }
    
    func suggestedEntities() async throws -> [FriendEntity] {
        return loadFriendsFromAppGroup()
    }
    
    /// Load friends from App Group shared data
    private func loadFriendsFromAppGroup() -> [FriendEntity] {
        guard let defaults = UserDefaults(suiteName: "group.com.nock.nock"),
              let data = defaults.data(forKey: "friends_list"),
              let friends = try? JSONDecoder().decode([FriendData].self, from: data) else {
            // Return placeholder if no friends cached
            return [
                FriendEntity(id: "demo1", name: "Best Friend", avatarUrl: nil),
                FriendEntity(id: "demo2", name: "Partner", avatarUrl: nil)
            ]
        }
        
        return friends.map { FriendEntity(id: $0.id, name: $0.name, avatarUrl: $0.avatarUrl) }
    }
}

// MARK: - Friend Data (Codable)
struct FriendData: Codable {
    let id: String
    let name: String
    let avatarUrl: String?
}

// MARK: - Select Friend Intent
/// Configuration intent for the BFF widget - allows user to pick which friend
struct SelectFriendIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Friend"
    static var description = IntentDescription("Choose which friend this widget connects to")
    
    @Parameter(title: "Friend")
    var friend: FriendEntity?
}
