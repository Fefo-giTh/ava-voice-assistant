import AppKit
import AVFoundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let talk = Self("talk", default: parseHotkey(Config.shared.hotkey) ?? .init(.space, modifiers: .control))
    static let cancel = Self("cancel", default: .init(.escape))
}

/// "control+space", "option+shift+a", "command+1"… → atalho. nil se não entender.
func parseHotkey(_ text: String) -> KeyboardShortcuts.Shortcut? {
    var mods: NSEvent.ModifierFlags = []
    var key: KeyboardShortcuts.Key?
    for part in text.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
        switch part {
        case "control", "ctrl": mods.insert(.control)
        case "option", "alt": mods.insert(.option)
        case "command", "cmd": mods.insert(.command)
        case "shift": mods.insert(.shift)
        case "space": key = .space
        default:
            let named: [String: KeyboardShortcuts.Key] = [
                "a": .a, "b": .b, "c": .c, "d": .d, "e": .e, "f": .f, "g": .g, "h": .h, "i": .i, "j": .j, "k": .k,
                "l": .l, "m": .m, "n": .n, "o": .o, "p": .p, "q": .q, "r": .r, "s": .s, "t": .t, "u": .u, "v": .v,
                "w": .w, "x": .x, "y": .y, "z": .z, "0": .zero, "1": .one, "2": .two, "3": .three, "4": .four,
                "5": .five, "6": .six, "7": .seven, "8": .eight, "9": .nine,
            ]
            guard let k = named[part] else { return nil }
            key = k
        }
    }
    guard let key, !mods.isEmpty else { return nil }  // sem modificador roubaria a tecla de todos os apps
    return .init(key, modifiers: mods)
}

let defaultVoice = Config.shared.voice

/// dB → 0...1 (-50 dB → 0, -10 dB → 1), igual para microfone e fala.
func level(fromDB db: Float) -> Float { max(0, min(1, (db + 50) / 40)) }

/// Captura o microfone; entrega nível (0...1) e amostras na main thread.
final class Microphone {
    private let engine = AVAudioEngine()
    private(set) var isRunning = false
    private(set) var sampleRate = 48000
    var onAudio: ((Float, [Float]) -> Void)?

    func start() throws {
        guard !isRunning else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        sampleRate = Int(format.sampleRate)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buf, _ in
            guard let ch = buf.floatChannelData?[0], buf.frameLength > 0 else { return }
            let chunk = Array(UnsafeBufferPointer(start: ch, count: Int(buf.frameLength)))
            let rms = (chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count)).squareRoot()
            let lvl = level(fromDB: 20 * log10(max(rms, 1e-7)))
            DispatchQueue.main.async { self?.onAudio?(lvl, chunk) }
        }
        do {
            try engine.start()
            isRunning = true
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }
}

/// Sessão de conversa: Control+Espaço liga (Aguardando) e desliga (invisível).
/// Com a sessão ligada, falar já começa a gravar; a Ava responde frase por frase e volta a aguardar.
final class Conversation: NSObject, AVAudioPlayerDelegate {
    // Calibração: nível acima disso conta como voz. Ajuste se cortar cedo (abaixe) ou disparar com ruído (suba).
    static let voiceThreshold: Float = 0.3
    static let silenceToStop: TimeInterval = 0.9
    static let preRoll: TimeInterval = 0.4  // guarda o começo da fala de antes do disparo
    static let echoGuard: TimeInterval = 0.5  // ignora o microfone logo depois que a Ava para de falar
    static let sessionTimeout: TimeInterval = 5 * 60  // fecha a sessão esquecida sem ninguém falar

    private let orb: OrbRenderer
    private let mic = Microphone()
    let brain = Brain()
    let server = Server()
    private let warningVoice = AVSpeechSynthesizer()  // voz do macOS: funciona mesmo com o servidor desligado

    private var active = false
    private var samples: [Float] = []
    private var preRollBuffer: [Float] = []
    private var loudChunks = 0
    private var silenceStart: Date?
    private var armedAt = Date()
    private var lastSpeech = Date()
    private var turn = 0  // tudo de um turno cancelado é descartado

    // Fila de fala do turno atual.
    private var players: [AVAudioPlayer] = []
    private var player: AVAudioPlayer?
    private var meter: Timer?
    private var synthTail: Task<Void, Never>?
    private var synthPending = 0
    private var brainDone = false

    init(orb: OrbRenderer) {
        self.orb = orb
        super.init()
        KeyboardShortcuts.onKeyDown(for: .talk) { [weak self] in self?.toggleSession() }
        KeyboardShortcuts.onKeyDown(for: .cancel) { [weak self] in self?.escPressed() }
        KeyboardShortcuts.disable(.cancel)
        mic.onAudio = { [weak self] in self?.heard($0, $1) }
        orb.onStateChange = { state in
            // Esc só fica registrado fora do Repouso, para não roubar o Esc dos outros apps.
            state == .repouso ? KeyboardShortcuts.disable(.cancel) : KeyboardShortcuts.enable(.cancel)
        }
    }

    // MARK: - Sessão

    private func toggleSession() {
        active ? endSession() : startSession()
    }

    private func startSession() {
        Task { try? await server.ensureRunning() }  // liga o servidor de voz já
        brain.warmUp()  // e abre o Claude, para a primeira resposta sair rápido
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard granted else {
                    fail("Preciso de acesso ao microfone. Libere em Ajustes do Sistema, Privacidade, Microfone.")
                    return
                }
                do { try mic.start() } catch { fail("Não consegui usar o microfone."); return }
                active = true
                orb.afterError = .aguardando
                lastSpeech = Date()
                await_()
            }
        }
    }

    private func endSession() {
        active = false
        orb.afterError = .repouso
        cancelTurn()
        mic.stop()
        orb.state = .repouso
    }

    /// Esc: cancela a resposta em andamento; se não houver, fecha a sessão.
    private func escPressed() {
        switch orb.state {
        case .pensando, .falando: cancelTurn(); await_()
        default: endSession()
        }
    }

    /// Volta a aguardar a próxima fala.
    private func await_() {
        guard active else { orb.state = .repouso; return }
        samples = []
        preRollBuffer = []
        loudChunks = 0
        armedAt = Date().addingTimeInterval(Self.echoGuard)
        orb.amplitude = 0
        orb.state = .aguardando
    }

    private func cancelTurn() {
        turn += 1
        brain.interrupt()
        synthTail = nil
        synthPending = 0
        players = []
        meter?.invalidate()
        meter = nil
        player?.stop()
        player = nil
    }

    // MARK: - Ouvir

    private func heard(_ level: Float, _ chunk: [Float]) {
        let now = Date()
        switch orb.state {
        case .aguardando:
            preRollBuffer += chunk
            let keep = Int(Self.preRoll * Double(mic.sampleRate))
            if preRollBuffer.count > keep { preRollBuffer.removeFirst(preRollBuffer.count - keep) }
            guard now >= armedAt else { return }
            // Dois blocos seguidos acima do limiar (~40 ms) para não disparar com um clique.
            loudChunks = level > Self.voiceThreshold ? loudChunks + 1 : 0
            if loudChunks >= 2 {
                samples = preRollBuffer
                silenceStart = nil
                orb.state = .ouvindo
            } else if now.timeIntervalSince(lastSpeech) > Self.sessionTimeout {
                endSession()
            }
        case .ouvindo:
            samples += chunk
            orb.amplitude = level
            if level > Self.voiceThreshold {
                silenceStart = nil
            } else {
                if silenceStart == nil { silenceStart = now }
                if now.timeIntervalSince(silenceStart!) >= Self.silenceToStop { finishListening() }
            }
        default:
            break  // pensando/falando: o microfone fica ligado, mas ignorado (não ouve a própria voz)
        }
    }

    // MARK: - Pensar e falar

    private func finishListening() {
        lastSpeech = Date()
        let wav = Backend.wav(samples, sampleRate: mic.sampleRate)
        orb.state = .pensando
        turn += 1
        let myTurn = turn
        brainDone = false
        var buffer = "", spokeSomething = false
        Task { @MainActor in
            do {
                try await server.ensureRunning()
                let text = try await Backend.transcribe(wav)
                guard myTurn == turn else { return }
                NSLog("Ava transcreveu: %@", text)
                guard Self.isRealSpeech(text) else { await_(); return }  // ruído: volta a aguardar em silêncio
                let reply = try await brain.ask(text) { piece in
                    guard myTurn == self.turn else { return }
                    buffer += piece
                    if let ready = Brain.takeSpeakable(from: &buffer) {
                        let s = Brain.cleanForSpeech(ready)
                        if !s.isEmpty { spokeSomething = true; self.enqueueSpeech(s, turn: myTurn) }
                    }
                }
                guard myTurn == turn else { return }
                NSLog("Ava respondeu: %@", reply)
                let rest = Brain.cleanForSpeech(buffer)
                if !rest.isEmpty { spokeSomething = true; enqueueSpeech(rest, turn: myTurn) }
                if Brain.copyBlocks(from: reply), !spokeSomething {
                    enqueueSpeech("Deixei na sua área de transferência.", turn: myTurn)
                }
                brainDone = true
                finishTurnIfDone()
            } catch is CancellationError {
                // Esc ou fim da sessão: nada a dizer.
            } catch is BrainFailed {
                if myTurn == turn { fail("Não consegui falar com o Claude. Confira sua internet e tente de novo.") }
            } catch is ServerDown {
                if myTurn == turn { fail("Não consegui ligar meu servidor de voz.") }
            } catch {
                if myTurn == turn { fail("Tive um problema para responder. Tente de novo.") }
            }
        }
    }

    /// Ruído às vezes vira texto inventado pelo Whisper; isso não vai para o Claude.
    static func isRealSpeech(_ text: String) -> Bool {
        let t = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let hallucinations = ["amara.org", "legendas pela comunidade", "inscreva-se", "obrigado por assistir"]
        return t.count >= 2 && !hallucinations.contains { t.contains($0) }
    }

    /// Sintetiza as frases em ordem (uma de cada vez) e põe na fila para tocar.
    private func enqueueSpeech(_ sentence: String, turn myTurn: Int) {
        let voice = UserDefaults.standard.string(forKey: "voice") ?? defaultVoice
        let previous = synthTail
        synthPending += 1
        synthTail = Task { @MainActor in
            await previous?.value
            defer { if myTurn == turn { synthPending -= 1; finishTurnIfDone() } }
            guard myTurn == turn, let audio = try? await Backend.synthesize(sentence, voice: voice),
                  myTurn == turn, let p = try? AVAudioPlayer(data: audio) else { return }
            p.delegate = self
            p.isMeteringEnabled = true
            players.append(p)
            playNext()
        }
    }

    private func playNext() {
        guard player == nil, !players.isEmpty else { return }
        let p = players.removeFirst()
        player = p
        orb.state = .falando
        p.play()
        if meter == nil {
            meter = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                guard let p = self?.player else { return }
                p.updateMeters()
                self?.orb.amplitude = level(fromDB: p.averagePower(forChannel: 0))
            }
        }
    }

    func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        guard p === player else { return }
        player = nil
        playNext()
        finishTurnIfDone()
    }

    /// Terminou de pensar, sintetizar e tocar tudo: volta a aguardar.
    private func finishTurnIfDone() {
        guard brainDone, synthPending == 0, players.isEmpty, player == nil,
              orb.state == .falando || orb.state == .pensando else { return }
        meter?.invalidate()
        meter = nil
        lastSpeech = Date()
        await_()
    }

    /// Pisca o Erro e avisa em voz alta.
    private func fail(_ message: String) {
        orb.state = .erro
        let u = AVSpeechUtterance(string: message)
        // Voz masculina do macOS para combinar com a pm_alex; cai para qualquer voz pt-BR se não existir.
        u.voice = AVSpeechSynthesisVoice.speechVoices().first { $0.language == "pt-BR" && $0.name.hasPrefix("Eddy") }
            ?? AVSpeechSynthesisVoice(language: "pt-BR")
        warningVoice.stopSpeaking(at: .immediate)
        warningVoice.speak(u)
    }
}
