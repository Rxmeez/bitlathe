import SwiftUI
import BitlatheCore
import BitlatheUI

/// Custom views for tools that outgrow the generic screen.
@MainActor
enum ToolViews {
    static func registerAll() {
        DiffToolViewRegistration.register()
    }
}
