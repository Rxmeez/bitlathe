// bl-advisor: the one place Bitlathe talks to a language model, and only to the one built into macOS (Apple
// Intelligence, on this Mac, no network). It is a separate helper because that framework needs a newer SDK than the
// app is built with; built without it, the helper simply reports that no model is available.
//
//   bl-advisor --status          prints "available" (exit 0) or "unavailable: <why>" (exit 3)
//   bl-advisor < query.json      {"instructions": "...", "prompt": "..."} on stdin; prints the model's reply
//
// It has no knowledge of Bitlathe's tools: the app builds the prompt and checks the reply (SmartBox.Advisor).
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum Exit { static let ok: Int32 = 0, failed: Int32 = 1, usage: Int32 = 2, unavailable: Int32 = 3 }

func finish(_ code: Int32, _ message: String, toError: Bool = false) -> Never {
    FileHandle(fileDescriptor: toError ? 2 : 1).write(Data((message + "\n").utf8))
    exit(code)
}

/// Nil when the model can be used; otherwise why not, in words a person can act on.
func unavailableReason() -> String? {
    #if canImport(FoundationModels)
    guard #available(macOS 26.0, *) else { return "needs macOS 26 or later" }
    switch SystemLanguageModel.default.availability {
    case .available: return nil
    case .unavailable(.deviceNotEligible): return "this Mac does not support Apple Intelligence"
    case .unavailable(.appleIntelligenceNotEnabled): return "Apple Intelligence is switched off in System Settings"
    case .unavailable(.modelNotReady): return "the model is still downloading or preparing"
    case .unavailable(let other): return "unavailable (\(other))"
    }
    #else
    return "this copy was built without on-device model support"
    #endif
}

let arguments = CommandLine.arguments.dropFirst()
if arguments.first == "--status" {
    if let why = unavailableReason() { finish(Exit.unavailable, "unavailable: \(why)") }
    finish(Exit.ok, "available")
}
guard arguments.isEmpty else { finish(Exit.usage, "usage: bl-advisor --status | bl-advisor < query.json", toError: true) }

let input = FileHandle.standardInput.readDataToEndOfFile()
guard let query = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
      let instructions = query["instructions"] as? String, let prompt = query["prompt"] as? String else {
    finish(Exit.usage, "expected {\"instructions\": …, \"prompt\": …} on stdin", toError: true)
}
if let why = unavailableReason() { finish(Exit.unavailable, "unavailable: \(why)") }

#if canImport(FoundationModels)
if #available(macOS 26.0, *) {
    do {
        let session = LanguageModelSession(instructions: instructions)
        // Routing is a lookup, not creative writing: the most likely answer, and a short one.
        var options = GenerationOptions()
        options.temperature = 0
        options.maximumResponseTokens = 80
        let response = try await session.respond(to: prompt, options: options)
        finish(Exit.ok, response.content)
    } catch {
        finish(Exit.failed, "model error: \(error.localizedDescription)", toError: true)
    }
}
#endif
finish(Exit.unavailable, "unavailable")
