import SwiftUI
import AppKit
import BitlatheCore
import BitlatheUI

/// Drives the welcome sheet. Shown once on first launch; reopened from Help > Show Welcome.
@MainActor
@Observable
final class OnboardingController {
    static let shared = OnboardingController()
    var isPresented = false

    func presentIfFirstLaunch() {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "BLOnboarding") { isPresented = true; return }
        // Screenshot harness runs of other tools must not be covered by the sheet.
        if UserDefaults.standard.string(forKey: "BLTool") != nil { return }
        #endif
        if !Settings.shared.onboardingCompleted { isPresented = true }
    }

    func finish() {
        Settings.shared.onboardingCompleted = true
        isPresented = false
    }
}

struct OnboardingView: View {
    @State private var page = 0
    @State private var settings = Settings.shared
    private let pageCount = 3
    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch page {
                case 0: DetectionDemoPage().transition(slide)
                case 1: ShortcutsPage().transition(slide)
                default: PrivacyPage(settings: settings).transition(slide)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, Space.xxl)
            .padding(.top, Space.xxl)

            HStack {
                Button("Skip", action: onFinish)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .opacity(page == pageCount - 1 ? 0 : 1)
                    .accessibilityHidden(page == pageCount - 1)
                Spacer()
                HStack(spacing: Space.sm) {
                    ForEach(0..<pageCount, id: \.self) { i in
                        Circle().fill(i == page ? Color.accentColor : Color.secondary.opacity(0.3)).frame(width: 7, height: 7)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step \(page + 1) of \(pageCount)")
                Spacer()
                Button(page == pageCount - 1 ? "Get Started" : "Continue") { advance() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(Space.xl)
        }
        .frame(width: 580, height: 440)
        .onExitCommand(perform: onFinish)
    }

    private var slide: AnyTransition {
        Motion.animation() == nil ? .identity : .opacity.combined(with: .offset(x: 24))
    }

    private func advance() {
        if page == pageCount - 1 { onFinish(); return }
        withAnimation(Motion.animation(Motion.normal)) { page += 1 }
    }
}

// MARK: - Shared page chrome

private struct PageHeader: View {
    let symbol: String?
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: Space.md) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            } else {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 64, height: 64)
                    .accessibilityHidden(true)
            }
            Text(title).font(.title.weight(.semibold)).multilineTextAlignment(.center)
            Text(subtitle).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 1. Detection demo

private struct DetectionDemoPage: View {
    private let demos = [
        "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.dBjftJeZ4CVP",
        "{\"name\":\"bitlathe\",\"fast\":true}",
        "#3D7BFF",
        "1700000000",
    ]
    @State private var index = 0
    private let timer = Timer.publish(every: 2.6, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: Space.xl) {
            PageHeader(symbol: nil, title: "Paste and it just works",
                       subtitle: "Bitlathe looks at what you paste and opens the right tool. Nothing to pick, nothing to configure.")
            VStack(alignment: .leading, spacing: Space.md) {
                Text(demos[index])
                    .font(Typography.captionMono)
                    .lineLimit(1).truncationMode(.middle)
                    .padding(Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.editorBackground, in: RoundedRectangle(cornerRadius: Radius.medium))
                    .overlay(RoundedRectangle(cornerRadius: Radius.medium).stroke(Palette.separator))
                HStack(spacing: Space.sm) {
                    Image(systemName: "wand.and.stars").foregroundStyle(Color.accentColor)
                    Text("Detected").foregroundStyle(.secondary)
                    ForEach(Array(detected.prefix(3).enumerated()), id: \.offset) { i, name in
                        Text(name)
                            .font(.callout.weight(i == 0 ? .semibold : .regular))
                            .padding(.horizontal, Space.sm).padding(.vertical, Space.xs)
                            .background(i == 0 ? Color.accentColor.opacity(0.18) : Palette.raised, in: RoundedRectangle(cornerRadius: Radius.small))
                    }
                    Spacer()
                }
            }
            .padding(Space.lg)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.large))
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
        .onReceive(timer) { _ in
            guard Motion.animation() != nil else { return }
            withAnimation(Motion.animation(Motion.fast)) { index = (index + 1) % demos.count }
        }
        .onTapGesture { index = (index + 1) % demos.count }
    }

    private var detected: [String] {
        DetectionEngine.detect(demos[index], tools: ToolRegistry.shared.tools).results.map(\.tool.name)
    }
}

// MARK: - 2. Shortcuts

private struct ShortcutsPage: View {
    private let tips: [(keys: String, text: String)] = [
        ("⌘K", "Open the command palette: every tool and action"),
        ("⌘⌥V", "Smart Paste: paste into the best matching tool"),
        ("⇧⌘D", "Detect what is on the clipboard right now"),
        ("⇧⌘C", "Copy the output"),
        ("⌘+  ⌘−", "Zoom the editor text"),
    ]
    var body: some View {
        VStack(spacing: Space.xl) {
            PageHeader(symbol: "command", title: "⌘K reaches everything",
                       subtitle: "Type a few letters to jump to any tool, run an action or switch a setting. Your hands never leave the keyboard.")
            VStack(spacing: 0) {
                ForEach(Array(tips.enumerated()), id: \.offset) { i, tip in
                    HStack(spacing: Space.md) {
                        Text(tip.keys)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .frame(width: 84)
                            .padding(.vertical, Space.xs)
                            .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.small))
                        Text(tip.text).font(.body)
                        Spacer()
                    }
                    .padding(.vertical, Space.sm)
                    if i < tips.count - 1 { Divider() }
                }
            }
            .padding(.horizontal, Space.lg).padding(.vertical, Space.xs)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.large))
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 3. Privacy

private struct PrivacyPage: View {
    @Bindable var settings: BitlatheCore.Settings
    var body: some View {
        VStack(spacing: Space.xl) {
            PageHeader(symbol: "lock.shield", title: "Everything stays on this Mac",
                       subtitle: "Bitlathe never uses the network. Nothing you paste is sent anywhere. Choose how much it remembers; change it any time in Settings.")
            VStack(spacing: 0) {
                choice("Detect the clipboard when Bitlathe comes forward",
                       detail: "Looks at what you copied and suggests a tool. Nothing is stored.",
                       isOn: $settings.detectOnFocus)
                Divider()
                choice("Keep a history of what I run",
                       detail: "Lets you go back to earlier inputs. Stored only on this Mac; sensitive tools are excluded.",
                       isOn: $settings.historyEnabled)
            }
            .padding(.horizontal, Space.lg).padding(.vertical, Space.xs)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.large))
            Spacer(minLength: 0)
        }
    }

    private func choice(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(title).font(.body)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .padding(.vertical, Space.md)
    }
}
