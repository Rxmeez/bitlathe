import SwiftUI
import BitlatheCore
import BitlatheUI

/// Custom views for tools that outgrow the generic screen.
@MainActor
enum ToolViews {
    static func registerAll() {
        ToolViewRegistry.register(RegexTool.id) { session in AnyView(RegexView(session: session)) }
        JSONTreeViewRegistration.register()
        DiffToolViewRegistration.register()
        ToolViewRegistry.register("csv.viewer") { session in AnyView(CSVTableView(session: session)) }
    }
}
