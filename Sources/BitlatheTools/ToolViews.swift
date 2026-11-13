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
        WebPreviewViews.register()
        for id in [GitHubActionsTool.id, KubernetesTool.id] {
            ResultViewRegistry.register(id) { session, output in AnyView(DiagramResultView(session: session, output: output)) }
            ToolViewRegistry.register(id) { session in AnyView(DiagramResultView.Screen(session: session)) }
        }
    }
}
