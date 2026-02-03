import AppIntents
import Foundation

// MARK: - Record Vibe Intent
/// App Intent triggered when user taps the BFF widget
/// Opens the app directly into recording mode for the specified friend
struct RecordVibeIntent: AppIntent {
    static var title: LocalizedStringResource = "Record Vibe"
    static var description = IntentDescription("Start recording a vibe to a friend")
    static var openAppWhenRun: Bool = true
    
    @Parameter(title: "Friend ID")
    var friendId: String
    
    init() {
        self.friendId = ""
    }
    
    init(friendId: String) {
        self.friendId = friendId
    }
    
    func perform() async throws -> some IntentResult {
        // The app will handle the deep link via URL scheme
        // nock://record?to=friendId
        // This is handled in AppDelegate/SceneDelegate
        
        // Store the target friend ID for the app to read on launch
        if let defaults = UserDefaults(suiteName: "group.com.nock.nock") {
            defaults.set(friendId, forKey: "pending_record_to")
            defaults.set(Date().timeIntervalSince1970, forKey: "pending_record_timestamp")
        }
        
        return .result()
    }
}

// MARK: - Send Nudge Intent  
/// Quick nudge action from BFF widget (iOS 17+ interactive widget)
struct SendNudgeIntent: AppIntent {
    static var title: LocalizedStringResource = "Send Nudge"
    static var description = IntentDescription("Send a quick nudge to your friend")
    
    @Parameter(title: "Friend ID")
    var friendId: String
    
    @Parameter(title: "Nudge Type")
    var nudgeType: String
    
    init() {
        self.friendId = ""
        self.nudgeType = "heart"
    }
    
    init(friendId: String, nudgeType: String = "heart") {
        self.friendId = friendId
        self.nudgeType = nudgeType
    }
    
    func perform() async throws -> some IntentResult {
        // Store nudge request for app to process
        if let defaults = UserDefaults(suiteName: "group.com.nock.nock") {
            defaults.set(friendId, forKey: "pending_nudge_to")
            defaults.set(nudgeType, forKey: "pending_nudge_type")
            defaults.set(Date().timeIntervalSince1970, forKey: "pending_nudge_timestamp")
        }
        
        // Trigger haptic feedback would happen in the main app
        return .result()
    }
}
