import SwiftUI
import BitlatheCore

/// Content of an extra window: its own AppModel (so selection and sessions are independent), opened on one tool.
struct ToolWindowRoot: View {
    let value: String?
    @State private var model: AppModel?

    var body: some View {
        Group {
            if let model {
                ContentView().environment(model)
            } else {
                Color.clear
            }
        }
        .onAppear {
            guard model == nil else { return }
            let m = AppModel()
            if let id = value?.split(separator: "#").first.map(String.init) { m.open(toolID: id) }
            model = m
        }
    }
}
