import Foundation

struct ServerDown: Error {}

/// Liga o servidor de voz da Ava (backend/server.py). Ele mesmo se desliga após 10 min sem uso
/// para liberar ~1,9 GB de RAM; o app religa quando você volta a falar.
@MainActor
final class Server {
    // O build-app.sh grava no Info.plist onde o repositório está.
    private static let backend = URL(fileURLWithPath:
        Bundle.main.object(forInfoDictionaryKey: "AvaBackendDir") as? String ?? NSHomeDirectory() + "/ava-voice-assistant/backend")

    private var process: Process?
    private var starting: Task<Void, Error>?

    /// Garante o servidor de pé; espera até 2 min pelo carregamento dos modelos.
    func ensureRunning() async throws {
        if let starting { return try await starting.value }
        if await Self.isUp() { return }
        let task = Task {
            try launch()
            for _ in 0..<120 {
                try await Task.sleep(for: .seconds(1))
                if await Self.isUp() { return }
            }
            throw ServerDown()
        }
        starting = task
        defer { starting = nil }
        try await task.value
    }

    func stopNow() { process?.terminate() }

    private func launch() throws {
        let p = Process()
        p.executableURL = Self.backend.appendingPathComponent(".venv/bin/python")
        p.arguments = ["-I", Self.backend.appendingPathComponent("server.py").path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        process = p
    }

    private static func isUp() async -> Bool {
        var req = URLRequest(url: Backend.speech.appendingPathComponent("health"))
        req.timeoutInterval = 2
        return (try? await URLSession.shared.data(for: req).1 as? HTTPURLResponse)?.statusCode == 200
    }
}
