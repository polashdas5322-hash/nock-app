import WidgetKit
import SwiftUI

@main
struct VibeWidgetBundle: WidgetBundle {
    var body: some Widget {
        VibeWidget()    // Shows latest vibe (existing)
        BFFWidget()     // Direct contact widget
        SquadWidget()   // NEW: Vibe feed widget
    }
}
