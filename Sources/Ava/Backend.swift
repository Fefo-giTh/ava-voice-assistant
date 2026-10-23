import Foundation

/// Fala com o servidor de voz da Ava (backend/server.py, porta 8000).
enum Backend {
    static let speech = URL(string: "http://127.0.0.1:8000/v1/speech/")!

    static func transcribe(_ wav: Data) async throws -> String {
        var req = URLRequest(url: speech.appendingPathComponent("transcribe"))
        req.httpMethod = "POST"
        req.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        let (data, resp) = try await URLSession.shared.upload(for: req, from: wav)
        try check(resp)
        struct Result: Decodable { let text: String }
        return try JSONDecoder().decode(Result.self, from: data).text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func synthesize(_ text: String, voice: String) async throws -> Data {
        var req = URLRequest(url: speech.appendingPathComponent("synthesize"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["text": text, "voice_id": voice])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try check(resp)
        return data
    }

    private static func check(_ resp: URLResponse) throws {
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    }

    /// WAV PCM 16-bit mono.
    static func wav(_ samples: [Float], sampleRate: Int) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        d.append(Data("RIFF".utf8)); u32(36 + bytes); d.append(Data("WAVEfmt ".utf8))
        u32(16); u16(1); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        d.append(Data("data".utf8)); u32(bytes)
        for s in samples { u16(UInt16(bitPattern: Int16(max(-1, min(1, s)) * 32767))) }
        return d
    }
}
