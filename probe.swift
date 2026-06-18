import FoundationModels
import Foundation

let model = SystemLanguageModel.default
print("on-device availability:", model.availability)

let caps = model.capabilities
print("  cap.vision:", caps.contains(.vision))
print("  cap.guidedGeneration:", caps.contains(.guidedGeneration))
print("  cap.reasoning:", caps.contains(.reasoning))
print("  cap.toolCalling:", caps.contains(.toolCalling))
print("  supportedLanguages:", model.supportedLanguages.count)

let pcc = PrivateCloudComputeLanguageModel()
print("PrivateCloudCompute available:", pcc.isAvailable)

let sema = DispatchSemaphore(value: 0)
Task {
    defer { sema.signal() }
    guard case .available = model.availability else {
        print("generation: SKIPPED (model not available)")
        return
    }
    do {
        let session = LanguageModelSession(model: model)
        let start = Date()
        let resp = try await session.respond(to: "Reply with exactly the two characters: OK")
        print("generation OK in \(String(format: "%.2f", -start.timeIntervalSinceNow))s ->", resp.content)
    } catch {
        print("generation error:", error)
    }
}
sema.wait()
