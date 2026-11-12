import Foundation
import CryptoKit
import BitlatheCore

public struct PKCETool: DevTool {
    public static let id = "oauth.pkce"
    public static let name = "OAuth PKCE"
    public static let summary = "Generate a PKCE code verifier and S256 challenge, plus state and nonce values — or verify a pair"
    public static let category = ToolCategory.generate
    public static let symbol = "person.badge.key"
    public static let keywords = ["pkce", "oauth", "oidc", "code verifier", "code challenge", "s256", "state", "nonce", "authorization code"]
    public static let io = ToolIO(input: .text, output: .text, acceptsFiles: false)
    public static let samples = [ToolSample("Verify a verifier", "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")]
    public static let optionFields: [OptionField] = [
        .stepper("length", "Verifier length", min: 43, max: 128, default: 64),
        .segmented("method", "Method", [.init("S256", "S256"), .init("plain", "plain")], default: "S256"),
        .text("clientId", "Client ID", placeholder: "for the example URL", advanced: true),
        .text("authorizeURL", "Authorize URL", placeholder: "https://auth.example.com/authorize", advanced: true),
        .text("redirectURI", "Redirect URI", placeholder: "myapp://callback", advanced: true),
        .text("scope", "Scope", placeholder: "openid profile", advanced: true),
    ]
    public struct Options: ToolOptions {
        public var length = 64
        public var method = "S256"
        public var clientId = ""
        public var authorizeURL = ""
        public var redirectURI = ""
        public var scope = ""
        public init() {}
    }
    public init() {}

    public static func challenge(for verifier: String, method: String = "S256") -> String {
        method == "plain" ? verifier : Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
    }

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let unreserved = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let provided = input.text.trimmed()
        let verifier: String
        var rows: [MetaRow] = []
        if !provided.isEmpty {
            verifier = provided
            let valid = provided.count >= 43 && provided.count <= 128 && provided.allSatisfy { unreserved.contains($0) }
            rows.append(MetaRow("Verifier check", valid ? "Valid (\(provided.count) chars, unreserved characters only)" : "Invalid: must be 43–128 chars of A-Z a-z 0-9 - . _ ~", style: valid ? .success : .danger))
        } else {
            verifier = String((0..<options.length).map { _ in unreserved[RandomStringTool.randomIndex(unreserved.count)] })
        }
        let challenge = Self.challenge(for: verifier, method: options.method)
        let state = RandomStringTool.randomBytes(24).base64URL
        let nonce = RandomStringTool.randomBytes(24).base64URL
        rows += [
            MetaRow("code_verifier", verifier, style: .mono), MetaRow("code_challenge", challenge, style: .mono), MetaRow("code_challenge_method", options.method, style: .mono),
            MetaRow("state", state, style: .mono), MetaRow("nonce", nonce, style: .mono),
            MetaRow("Entropy", String(format: "%.0f bits", Double(verifier.count) * log2(66))),
        ]
        var url = ""
        if !options.authorizeURL.isEmpty {
            var c = URLComponents(string: options.authorizeURL)
            c?.queryItems = [URLQueryItem(name: "response_type", value: "code"), URLQueryItem(name: "client_id", value: options.clientId), URLQueryItem(name: "redirect_uri", value: options.redirectURI),
                             URLQueryItem(name: "scope", value: options.scope.isEmpty ? "openid" : options.scope), URLQueryItem(name: "state", value: state), URLQueryItem(name: "nonce", value: nonce),
                             URLQueryItem(name: "code_challenge", value: challenge), URLQueryItem(name: "code_challenge_method", value: options.method)]
            url = c?.string ?? ""
            rows.append(MetaRow("Authorize URL", url, style: .mono))
        }
        let json = JSONSerializer.string(.object([(key: "code_verifier", value: .string(verifier)), (key: "code_challenge", value: .string(challenge)), (key: "code_challenge_method", value: .string(options.method)), (key: "state", value: .string(state)), (key: "nonce", value: .string(nonce))]))
        var facets = [OutputFacet("Verifier", text: verifier), OutputFacet("Challenge", text: challenge), OutputFacet("curl token exchange", text: "curl -X POST https://auth.example.com/token \\\n  -d grant_type=authorization_code \\\n  -d client_id=\(options.clientId.isEmpty ? "CLIENT_ID" : options.clientId) \\\n  -d code=AUTH_CODE \\\n  -d redirect_uri=\(options.redirectURI.isEmpty ? "REDIRECT_URI" : options.redirectURI) \\\n  -d code_verifier=\(verifier)", language: .shell)]
        if !url.isEmpty { facets.append(OutputFacet("Authorize URL", text: url)) }
        return ToolOutput(text: json, language: .json, facets: facets, metadata: rows)
    }
}
