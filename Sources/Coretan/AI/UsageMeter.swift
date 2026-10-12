import Foundation

/// Credit accounting. A failed request must never burn quota, so callers record
/// only after a successful response.
final class UsageMeter: ObservableObject {
    static let shared = UsageMeter()
    @Published private(set) var used: Int = 0
    @Published private(set) var byFeature: [String: Int] = [:]
    @Published private(set) var lastResetMonth: String = ""

    private let key = "coretan.usage"
    private let limitKey = "coretan.usage.limit"

    private struct Snapshot: Codable {
        var used: Int
        var byFeature: [String: Int]
        var month: String
    }

    init() {
        load()
        rollMonthIfNeeded()
    }

    var limit: Int {
        get { UserDefaults.standard.object(forKey: limitKey) as? Int ?? 500 }
        set { UserDefaults.standard.set(newValue, forKey: limitKey); objectWillChange.send() }
    }

    var remaining: Int { max(0, limit - used) }

    func canSpend() -> Bool {
        rollMonthIfNeeded()
        return used < limit
    }

    func record(tokens: Int, feature: String) {
        rollMonthIfNeeded()
        used += max(0, tokens)
        byFeature[feature, default: 0] += max(0, tokens)
        save()
    }

    func reset() { used = 0; byFeature = [:]; save() }

    private func rollMonthIfNeeded() {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"
        let month = fmt.string(from: Date())
        if month != lastResetMonth {
            used = 0; byFeature = [:]; lastResetMonth = month; save()
        }
    }

    private func load() {
        guard let d = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(Snapshot.self, from: d) else { return }
        used = s.used; byFeature = s.byFeature; lastResetMonth = s.month
    }

    private func save() {
        let s = Snapshot(used: used, byFeature: byFeature, month: lastResetMonth)
        if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: key) }
    }
}
