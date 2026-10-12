import Foundation

/// OpenAI-compatible client. Base URL and key live in Settings; the key is kept
/// in the Keychain, never in the bundle.
struct AIConfig: Codable, Equatable {
    var baseURL: String = "http://127.0.0.1:20128/v1"
    var model: String = "Jogun"
    var embedModel: String = "text-embedding-3-small"
    var transcriptionModel: String = "whisper-1"
    var imageModel: String = "gpt-image-1"
    var monthlyCreditLimit: Int = 500
}

final class AIClient {
    var config: AIConfig
    private let session: URLSession

    init(config: AIConfig = Settings.shared.ai) {
        self.config = config
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 90
        c.waitsForConnectivity = true
        self.session = URLSession(configuration: c)
    }

    struct Message: Codable { var role: String; var content: String }

    struct ChatRequest: Codable {
        var model: String
        var messages: [Message]
        var temperature: Double?
        var stream: Bool? = false
    }

    struct ChatResponse: Codable {
        struct Choice: Codable {
            struct Msg: Codable { var role: String?; var content: String? }
            var message: Msg?
        }
        var choices: [Choice]?
        var usage: Usage?
        struct Usage: Codable { var total_tokens: Int? }
    }

    enum AIError: LocalizedError {
        case missingKey
        case quotaExceeded(Int, Int)
        case http(Int, String)
        case badResponse(String)

        var errorDescription: String? {
            switch self {
            case .missingKey: return "API key belum diisi di Pengaturan."
            case .quotaExceeded(let used, let limit): return "Kuota AI habis (\(used)/\(limit)). Tambah kuota atau tunggu bulan berikutnya."
            case .http(let code, let body): return "Server menolak (\(code)): \(body.prefix(160))"
            case .badResponse(let s): return "Respons tidak dikenali: \(s.prefix(160))"
            }
        }
    }

    func chat(_ messages: [Message], temperature: Double = 0.3, maxTokens: Int = 1200) async throws -> String {
        guard let key = Keychain.get("coretan.ai.key"), !key.isEmpty else { throw AIError.missingKey }
        guard UsageMeter.shared.canSpend() else {
            throw AIError.quotaExceeded(UsageMeter.shared.used, config.monthlyCreditLimit)
        }
        guard let url = URL(string: config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions") else {
            throw AIError.badResponse("base URL tidak valid")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let body = ChatRequest(model: config.model, messages: messages, temperature: temperature)
        req.httpBody = try JSONEncoder().encode(body)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AIError.badResponse("no http") }
        guard (200..<300).contains(http.statusCode) else {
            throw AIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let text = decoded.choices?.first?.message?.content else {
            throw AIError.badResponse(String(data: data, encoding: .utf8) ?? "")
        }
        // charge only on success
        UsageMeter.shared.record(tokens: decoded.usage?.total_tokens ?? max(1, text.count / 4), feature: "chat")
        return text
    }

    // MARK: Audio transcription

    func transcribe(audioURL: URL) async throws -> [TranscriptSegment] {
        guard let key = Keychain.get("coretan.ai.key"), !key.isEmpty else { throw AIError.missingKey }
        guard let url = URL(string: config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/audio/transcriptions") else {
            throw AIError.badResponse("base URL tidak valid")
        }
        let boundary = "----coretan\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        field("model", config.transcriptionModel)
        field("response_format", "verbose_json")
        field("timestamp_granularities[]", "segment")
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        if let audio = try? Data(contentsOf: audioURL) { body.append(audio) }
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AIError.http((resp as? HTTPURLResponse)?.statusCode ?? -1, String(data: data, encoding: .utf8) ?? "")
        }
        struct Verbose: Codable {
            struct Seg: Codable { var start: Double?; var end: Double?; var text: String? }
            var text: String?
            var segments: [Seg]?
        }
        let v = try JSONDecoder().decode(Verbose.self, from: data)
        UsageMeter.shared.record(tokens: (v.text?.count ?? 0) / 4, feature: "transkripsi")
        return (v.segments ?? []).map { TranscriptSegment(start: $0.start ?? 0, end: $0.end ?? 0, text: ($0.text ?? "").trimmingCharacters(in: .whitespaces)) }
    }

    // MARK: Image generation

    func generateImage(prompt: String) async throws -> Data {
        guard let key = Keychain.get("coretan.ai.key"), !key.isEmpty else { throw AIError.missingKey }
        guard let url = URL(string: config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/images/generations") else {
            throw AIError.badResponse("base URL tidak valid")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": config.imageModel, "prompt": prompt, "size": "1024x1024", "n": 1
        ])
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AIError.http((resp as? HTTPURLResponse)?.statusCode ?? -1, String(data: data, encoding: .utf8) ?? "")
        }
        struct ImgResp: Codable {
            struct Item: Codable { var b64_json: String?; var url: String? }
            var data: [Item]?
        }
        let decoded = try JSONDecoder().decode(ImgResp.self, from: data)
        guard let item = decoded.data?.first else { throw AIError.badResponse("tanpa gambar") }
        if let b64 = item.b64_json, let d = Data(base64Encoded: b64) { return d }
        if let urlStr = item.url, let u = URL(string: urlStr) {
            let (imgData, _) = try await session.data(from: u)
            return imgData
        }
        throw AIError.badResponse("format gambar tidak dikenali")
    }
}

struct TranscriptSegment: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var start: Double
    var end: Double
    var text: String
    var speaker: String?
}
