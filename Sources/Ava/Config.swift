import Foundation

/// Configuração do agente em ~/.ava/config.json. Tudo é opcional; o que faltar usa o padrão.
///
///     {
///       "name": "Luna",
///       "voice": "pf_dora",
///       "hotkey": "option+space",
///       "palette": ["#07050D", ... 8 cores do escuro ao claro],
///       "mascot": { "rows": [...4 linhas de 18 caracteres, "#" corpo, "E" olho],
///                   "legs": [2 linhas de 18 caracteres, um quadro cada] }
///     }
struct Config: Decodable {
    var name = "Ava"
    var voice = "pm_alex"
    var hotkey = "control+space"
    var theme = Theme.default

    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ava/config.json")
    static let shared: Config = {
        guard let data = try? Data(contentsOf: url) else { return Config() }
        do { return try JSONDecoder().decode(Config.self, from: data) } catch {
            NSLog("Ava: config.json inválido, usando o padrão: %@", "\(error)")
            return Config()
        }
    }()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? name
        voice = try c.decodeIfPresent(String.self, forKey: .voice) ?? voice
        hotkey = try c.decodeIfPresent(String.self, forKey: .hotkey) ?? hotkey
        if let hex = try c.decodeIfPresent([String].self, forKey: .palette) {
            theme.palette = try hex.map(Theme.rgb)
            guard theme.palette.count == 8 else {
                throw DecodingError.dataCorruptedError(forKey: .palette, in: c, debugDescription: "a paleta precisa de 8 cores")
            }
        }
        if let m = try c.decodeIfPresent(Mascot.self, forKey: .mascot) {
            guard m.rows.count == 4, m.legs.count == 2, (m.rows + m.legs).allSatisfy({ $0.count == 18 }) else {
                throw DecodingError.dataCorruptedError(forKey: .mascot, in: c, debugDescription: "mascote: 4 linhas + 2 pernas, 18 caracteres cada")
            }
            theme.rows = m.rows
            theme.legs = m.legs
        }
    }

    private enum Keys: String, CodingKey { case name, voice, hotkey, palette, mascot }
    private struct Mascot: Decodable { let rows: [String]; let legs: [String] }
}

/// Cores e desenho do mascote.
struct Theme {
    typealias RGB = (r: UInt8, g: UInt8, b: UInt8)

    var palette: [RGB]
    var rows: [String]
    var legs: [String]

    /// Padrão público: fantasminha pixelado roxo.
    static let `default` = Theme(
        palette: ["#07050D", "#140C26", "#2A1852", "#4A2A96", "#7848DC", "#A86EFF", "#D696FF", "#FFECFF"].map { try! rgb($0) },
        rows: [
            "....##########....",
            "...##E######E##...",
            "..##############..",
            "..##############..",
        ],
        legs: [
            "..##.###..###.##..",
            "..###.##..##.###..",
        ])

    static func rgb(_ hex: String) throws -> RGB {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard s.count == 6, let v = UInt32(s, radix: 16) else { throw CocoaError(.formatting) }
        return (UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF))
    }
}
