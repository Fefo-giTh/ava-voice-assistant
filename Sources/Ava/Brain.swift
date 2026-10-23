import AppKit

struct BrainFailed: Error {}

/// Cérebro: Claude via Claude Code com o login do usuário, sem chave de API.
/// Fica com um `claude` aberto entre as perguntas (economiza ~1,2 s de inicialização por pergunta)
/// e entrega o texto em pedaços enquanto o Claude escreve. A sessão do Claude guarda o histórico.
final class Brain {
    static func prompt(name: String = Config.shared.name, obsidianVault: String?) -> String {
        """
        Você se chama \(name) e é o assistente pessoal por voz do usuário, no Mac dele. Se perguntarem seu nome, diga que é \(name).

        Fale sempre em português do Brasil. Seja direta, inteligente e eficiente.

        Suas respostas são FALADAS em voz alta, frase por frase, enquanto você escreve:
        - Comece com uma frase curta que já responda ou diga o que vai fazer.
        - Use frases curtas e naturais, como numa conversa.
        - Responda em 1 a 3 frases. Só se estenda se o usuário pedir.
        - Nunca use markdown, listas, asteriscos, emojis, links, tabelas ou código.
        - Escreva números e símbolos como se fala ("doze por cento", não "12%").
        - Sem bajulação: nada de "Claro!", "Ótima pergunta!". Vá direto ao ponto.

        Se algo curto não cabe em voz (um link, um comando, um trecho de código), coloque entre <copiar> e </copiar>. Vai para a área de transferência. Fora das marcas, diga só uma frase curta, por exemplo: "Deixei o link na sua área de transferência."
        \(obsidianVault.map { "Se for algo longo (resumo, lista, plano, texto), salve como nota Markdown na pasta \"\($0)/Ava\" com um título claro e diga só \"Salvei no Obsidian com o título tal\"." } ?? "")

        Se não souber ou não conseguir fazer algo, diga isso claramente.

        Arquivos: você pode ler, procurar, criar, editar e mover arquivos dentro da pasta pessoal do usuário.
        - Nunca apague nada de verdade. Para "apagar", mova para a Lixeira (~/.Trash).
        - Antes de mover para a Lixeira, sobrescrever um arquivo que já existe ou mexer em mais de cinco arquivos de uma vez, diga em uma frase o que vai fazer e pergunte "Posso?". Só faça depois que o usuário confirmar na mensagem seguinte.
        - O pedido do usuário vem de transcrição de voz e pode ter palavras erradas. Se estiver ambíguo, pergunte antes de agir.
        - Depois de agir, diga em uma frase o que fez e onde ficou.

        Para tarefas difíceis ou quando não tiver certeza, consulte o agente "consultor" antes de responder ou agir.
        """
    }

    // Trava técnica: sem comandos de apagar, e o sandbox só deixa o terminal escrever na pasta pessoal.
    static let settings = #"{"permissions":{"allow":["Read","Glob","Grep","Edit","Write","WebSearch","WebFetch","Agent","Task"],"deny":["Bash(rm:*)","Bash(rmdir:*)","Bash(sudo:*)","Bash(shred:*)","Bash(dd:*)","Bash(*-delete*)","Bash(srm:*)","Bash(unlink:*)"]},"sandbox":{"enabled":true,"autoAllowBashIfSandboxed":true}}"#
    // Haiku responde rápido; para tarefas difíceis ele consulta o Opus, que só lê e pesquisa.
    static let model = "haiku"
    static let agents = #"{"consultor":{"description":"Consultor Opus. Use para tarefas difíceis: raciocínio complexo, planejar como organizar muitos arquivos, analisar documentos longos ou código, ou quando não tiver certeza da resposta. Ele lê e pesquisa e devolve uma recomendação; quem age é você.","prompt":"Você é o consultor do assistente de voz. Analise o pedido, leia e pesquise o que precisar e devolva uma recomendação objetiva e curta, em português. Não altere arquivos.","model":"opus","tools":["Read","Glob","Grep","WebSearch","WebFetch"]}}"#
    static let idleLimit: TimeInterval = 10 * 60  // fecha o claude parado para liberar memória

    private var session = UUID().uuidString
    private var started = false  // a sessão já existe no disco (dá para --resume)
    private var process: Process?
    private var input: FileHandle?
    private var pending = Data()
    private var onText: ((String) -> Void)?
    private var onDone: ((Result<String, Error>) -> Void)?
    private var idleTimer: Timer?

    /// Abre o claude antes da primeira pergunta.
    func warmUp() {
        if process == nil { try? launch() }
    }

    /// Envia a pergunta; `onText` recebe o texto em pedaços enquanto o Claude escreve. Devolve o texto final.
    func ask(_ question: String, onText: @escaping (String) -> Void) async throws -> String {
        if process == nil { try launch() }
        resetIdleTimer()
        let line = try JSONSerialization.data(withJSONObject: ["type": "user", "message": ["role": "user", "content": question]])
        return try await withCheckedThrowingContinuation { cont in
            self.onText = onText
            self.onDone = { cont.resume(with: $0) }
            input?.write(line + Data("\n".utf8))
            NSLog("Ava ouviu: %@", question)
        }
    }

    /// Interrompe a resposta atual (Esc ou fim da sessão). O próximo `ask` reabre o claude na mesma conversa.
    func interrupt() {
        finish(.failure(CancellationError()))
        process?.terminate()
    }

    private func launch() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let vault = UserDefaults.standard.string(forKey: "obsidianVault").flatMap { $0.isEmpty ? nil : $0 }
        var args = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                    "--include-partial-messages", "--model", Self.model,
                    "--setting-sources", "local", "--strict-mcp-config",  // sem plugins, hooks nem MCP: mais rápido
                    "--settings", Self.settings, "--agents", Self.agents,
                    "--append-system-prompt", Self.prompt(obsidianVault: vault)]
        args += started ? ["--resume", session] : ["--session-id", session]

        let p = Process()
        // Onde o instalador oficial, o Homebrew ou o npm costumam colocar o claude.
        let candidates = [home.appendingPathComponent(".local/bin/claude").path, "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        guard let claude = candidates.first(where: FileManager.default.isExecutableFile) else { throw BrainFailed() }
        p.executableURL = URL(fileURLWithPath: claude)
        p.arguments = args
        p.currentDirectoryURL = home  // o Claude enxerga a pasta pessoal
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + home.appendingPathComponent(".local/bin").path
        p.environment = env
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            DispatchQueue.main.async { self?.consume(data) }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.exited(p) }
        }
        try p.run()
        process = p
        input = inPipe.fileHandleForWriting
        pending = Data()
        resetIdleTimer()
    }

    private func exited(_ p: Process) {
        guard p === process else { return }
        process = nil
        input = nil
        if !started { session = UUID().uuidString }  // morreu antes de criar a sessão: começa outra
        finish(.failure(BrainFailed()))
    }

    /// Lê as linhas JSON do claude: pedaços de texto e o resultado final.
    private func consume(_ data: Data) {
        pending.append(data)
        while let nl = pending.firstIndex(of: UInt8(ascii: "\n")) {
            let line = pending[pending.startIndex..<nl]
            pending.removeSubrange(pending.startIndex...nl)
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            switch obj["type"] as? String {
            case "stream_event" where obj["parent_tool_use_id"] is NSNull || obj["parent_tool_use_id"] == nil:
                // Só o texto da Ava; o do consultor (subagente) não é falado.
                if let event = obj["event"] as? [String: Any], event["type"] as? String == "content_block_delta",
                   let delta = event["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
                   let text = delta["text"] as? String {
                    onText?(text)
                }
            case "result":
                started = true
                if obj["is_error"] as? Bool == true {
                    finish(.failure(BrainFailed()))
                } else {
                    finish(.success(obj["result"] as? String ?? ""))
                }
            default:
                break
            }
        }
    }

    private func finish(_ result: Result<String, Error>) {
        let done = onDone
        onDone = nil
        onText = nil
        done?(result)
    }

    private func resetIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: Self.idleLimit, repeats: false) { [weak self] _ in
            self?.process?.terminate()
        }
    }

    // MARK: - Texto para voz

    /// Tira do buffer o trecho que já tem frases completas (fora de um <copiar> aberto) e devolve para falar.
    static func takeSpeakable(from buffer: inout String) -> String? {
        let enders: Set<Character> = [".", "!", "?", "…", ":", "\n"]
        var i = buffer.endIndex
        while i > buffer.startIndex {
            let prev = buffer.index(before: i)
            // Fim de frase = pontuação seguida de espaço (evita cortar "3.5").
            if enders.contains(buffer[prev]), i < buffer.endIndex, buffer[i].isWhitespace || buffer[prev] == "\n" {
                let head = String(buffer[..<i])
                if head.components(separatedBy: "<copiar>").count == head.components(separatedBy: "</copiar>").count {
                    buffer = String(buffer[i...])
                    return head
                }
            }
            i = prev
        }
        return nil
    }

    /// Remove o que não é para falar: blocos <copiar>, markdown e links.
    static func cleanForSpeech(_ text: String) -> String {
        text.replacingOccurrences(of: "<copiar>[\\s\\S]*?</copiar>|<think>[\\s\\S]*?</think>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[*#`_]|https?://\\S+", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Copia os blocos <copiar> da resposta para a área de transferência. Devolve se copiou algo.
    @discardableResult
    static func copyBlocks(from reply: String, pasteboard: NSPasteboard = .general) -> Bool {
        let re = try! NSRegularExpression(pattern: "<copiar>([\\s\\S]*?)</copiar>")
        let blocks = re.matches(in: reply, range: NSRange(reply.startIndex..., in: reply)).compactMap {
            Range($0.range(at: 1), in: reply).map { String(reply[$0]).trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        guard !blocks.isEmpty else { return false }
        pasteboard.clearContents()
        pasteboard.setString(blocks.joined(separator: "\n\n"), forType: .string)
        return true
    }
}
