import Foundation

/// Non-secret settings. The API key is separate (Keychain).
final class Settings {
    static let shared = Settings()
    private let key = "coretan.ai.config"

    var ai: AIConfig = AIConfig() {
        didSet { save() }
    }

    private init() { load() }

    private func load() {
        guard let d = UserDefaults.standard.data(forKey: key),
              let c = try? JSONDecoder().decode(AIConfig.self, from: d) else { return }
        ai = c
    }

    private func save() {
        if let d = try? JSONEncoder().encode(ai) { UserDefaults.standard.set(d, forKey: key) }
    }
}
