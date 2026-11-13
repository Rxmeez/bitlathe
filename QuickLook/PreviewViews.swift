import SwiftUI
import AppKit
import BitlatheCore
import BitlatheUI

struct PreviewRoot: View {
    let model: PreviewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch model.content {
            case .jwt(let j): JWTView(info: j)
            case .certificates(let certs, let notes): CertsView(certs: certs, notes: notes)
            case .csr(_, let rows): KeyValueList(rows)
            case .code(let text, let lang, let truncated, let notice): CodeView(text: text, language: lang, truncated: truncated, notice: notice)
            case .message(let m): Text(m).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity).padding()
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    var header: some View {
        HStack(spacing: Space.md) {
            Image(systemName: model.symbol).font(.title2).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title).font(.headline).lineLimit(1).truncationMode(.middle)
                Text(model.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if case .jwt(let j) = model.content, let s = j.status { Badge(text: s.text, tone: s.tone) }
        }
        .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
    }
}

struct Badge: View {
    let text: String
    let tone: PreviewModel.Tone
    var color: Color {
        switch tone { case .good: .green; case .bad: .red; case .warn: .orange; case .plain: .secondary }
    }
    var body: some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }
}

struct SectionTitle: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View { Text(text).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase) }
}

struct JWTView: View {
    let info: PreviewModel.JWTInfo
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                if info.unsigned {
                    Label("alg=none: this token is unsigned and must not be trusted", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout)
                }
                if !info.claims.isEmpty {
                    SectionTitle("Claims")
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.md, verticalSpacing: Space.xs) {
                        ForEach(info.claims) { c in
                            GridRow {
                                Text(c.name).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                                HStack(spacing: Space.sm) {
                                    Text(c.value).textSelection(.enabled)
                                    if let n = c.note { Badge(text: n, tone: c.tone) }
                                }
                            }
                        }
                    }
                }
                SectionTitle("Header")
                HighlightedText(text: info.header, language: .json)
                SectionTitle("Payload")
                HighlightedText(text: info.payload, language: .json)
            }
            .padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct CertsView: View {
    let certs: [PreviewModel.CertInfo]
    let notes: [String]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                ForEach(Array(certs.enumerated()), id: \.element.id) { i, c in
                    CertCard(cert: c, index: certs.count > 1 ? i + 1 : nil)
                    if i < certs.count - 1 { Divider() }
                }
                ForEach(notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct CertCard: View {
    let cert: PreviewModel.CertInfo
    let index: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                if let index { Text("#\(index)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                Text(cert.title).font(.title3.weight(.semibold)).textSelection(.enabled)
                Badge(text: cert.status.text, tone: cert.status.tone)
                ForEach(cert.badges, id: \.self) { Badge(text: $0, tone: .plain) }
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.md, verticalSpacing: Space.xs) {
                row("Subject", cert.subject)
                row("Issuer", cert.issuer)
                row("Validity", cert.validity)
                if !cert.sans.isEmpty { row("SANs", cert.sans.joined(separator: "\n")) }
                row("Public key", cert.key)
                row("Signature", cert.signature)
                row("Serial", cert.serial, mono: true)
                ForEach(cert.fingerprints, id: \.0) { fp in
                    row(fp.0, fp.1, mono: true)
                }
            }
            ForEach(cert.warnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
        }
    }

    func row(_ label: String, _ value: String, mono: Bool = false) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label).font(.callout).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).font(mono ? .system(.caption, design: .monospaced) : .callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct CodeView: View {
    let text: String
    let language: CodeLanguage
    let truncated: Bool
    let notice: String?
    var body: some View {
        GeometryReader { geo in
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    if let notice { Label(notice, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                    HighlightedText(text: text, language: language)
                    if truncated { Text("Preview truncated.").font(.caption).foregroundStyle(.secondary) }
                }
                .padding(Space.lg)
                .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
            }
        }
    }
}

/// Syntax-tinted monospaced text using the app's highlighter and editor theme (light/dark aware).
struct HighlightedText: View {
    let text: String
    let language: CodeLanguage
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(attributed).textSelection(.enabled).fixedSize(horizontal: true, vertical: false)
    }

    var attributed: AttributedString {
        let theme = EditorTheme.all[0]
        let colors = scheme == .dark ? theme.dark : theme.light
        let storage = NSMutableAttributedString(string: text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)])
        Highlighter.highlight(storage, language: language, colors: colors)
        return (try? AttributedString(storage, including: \.appKit)) ?? AttributedString(text)
    }
}
