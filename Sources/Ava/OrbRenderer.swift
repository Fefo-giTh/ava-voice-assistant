import CoreGraphics
import Foundation

enum OrbState: String, CaseIterable {
    case repouso = "Repouso", aguardando = "Aguardando", ouvindo = "Ouvindo", pensando = "Pensando", falando = "Falando", erro = "Erro"
}

// Bayer 4×4 normalizado para limiares em (0, 1).
private let bayer: [Float] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map { ($0 + 0.5) / 16 }

/// Estrelinha que gira enquanto pensa: · ✢ ✳ ✶ ✻ ✽ (ida e volta).
private let spinner: [[String]] = [
    [".......", ".......", ".......", "...#...", ".......", ".......", "......."],
    [".......", "...#...", "...#...", ".#####.", "...#...", "...#...", "......."],
    ["#..#..#", ".#.#.#.", "..###..", "#######", "..###..", ".#.#.#.", "#..#..#"],
    ["...#...", "#..#..#", ".#####.", "..###..", ".#####.", "#..#..#", "...#..."],
    [".#.#.#.", "##.#.##", "..###..", "###.###", "..###..", "##.#.##", ".#.#.#."],
    ["#..#..#", ".##.##.", ".#####.", "###.###", ".#####.", ".##.##.", "#..#..#"],
]
private let spinnerOrder = [0, 1, 2, 3, 4, 5, 4, 3, 2, 1]

/// Desenha o mascote em 44×44 px. Sem AppKit, para poder ser testado.
final class OrbRenderer {
    let theme: Theme
    init(theme: Theme = Config.shared.theme) { self.theme = theme }

    static let size = 44
    // Cada pixel do mascote vira 2×4: no terminal o caractere é 2× mais alto que largo.
    static let scaleX = 2, scaleY = 4

    var state: OrbState = .repouso {
        didSet {
            if state == .erro { errorStart = time }
            if state != oldValue { onStateChange?(state) }
        }
    }
    var onStateChange: ((OrbState) -> Void)?
    /// Para onde volta depois de piscar o Erro (Aguardando se a sessão estiver aberta).
    var afterError: OrbState = .repouso
    /// 0...1 — amplitude do microfone (Ouvindo) ou da fala (Falando).
    var amplitude: Float = 0

    private(set) var intensity: Float = 0
    private(set) var light: Float = 0
    private var thinking: Float = 0
    private var time: Float = 0
    private var errorStart: Float = 0

    func step(dt: Float = 1.0 / 60) {
        time += dt
        let k = dt * 60  // interpolação do spec é "por frame a 60 fps"; isso mantém o ritmo em telas de 120 Hz
        var targetI: Float = 0, targetL: Float = 0
        switch state {
        case .repouso: break
        case .ouvindo, .falando: targetI = amplitude; targetL = 1
        case .pensando: targetI = 0.5; targetL = 1
        case .aguardando: targetI = 0.2; targetL = 1
        case .erro:
            let e = time - errorStart
            if e > 0.9 {
                state = afterError
            } else {
                // Pisca duas vezes; sem suavização para o piscar ser nítido.
                light = e.truncatingRemainder(dividingBy: 0.45) < 0.22 ? 1 : 0
                intensity = light * 0.6
            }
        }
        if state != .erro {
            intensity += (targetI - intensity) * min(1, 0.1 * k)
            light += (targetL - light) * min(1, 0.06 * k)
        }
        thinking += ((state == .pensando || state == .aguardando ? 1 : 0) - thinking) * min(1, 0.1 * k)
    }

    /// RGBA pré-multiplicado, 44×44, linha 0 em cima.
    func pixels() -> [UInt8] {
        let n = Self.size, sx = Self.scaleX, sy = Self.scaleY
        var level = [Float](repeating: 0, count: n * n)
        var alpha = [Float](repeating: 0, count: n * n)
        let shift: Float = state == .erro ? -2 : 0
        let glow = light * (0.3 + 0.7 * intensity)

        // Mascote: sprite 18×5 ampliado para 36×20, embaixo; pula com a voz.
        let hop = Int((intensity * light * 3).rounded())
        let ox = (n - 18 * sx) / 2, oy = 18 - hop
        let legFrame = state == .falando ? Int(time * 6) % 2 : 0
        // No Pensando os olhos olham de um lado para o outro, como quem procura algo.
        let look = thinking > 0.5 ? (Int(time * 2.5) % 2 == 0 ? -1 : 1) : 0
        let rows = theme.rows + [theme.legs[legFrame]]
        let palette = theme.palette

        // Halo elíptico em volta do mascote, com borda em dithering.
        let cx = Float(n) / 2, cy = Float(oy + 10)
        for y in 0..<n {
            for x in 0..<n {
                let dx = (Float(x) + 0.5 - cx) / 20, dy = (Float(y) + 0.5 - cy) / 13
                let h = glow * 0.7 * exp(-max(0, (dx * dx + dy * dy).squareRoot() - 0.7) * 4)
                if h > bayer[(y % 4) * 4 + x % 4] {
                    level[y * n + x] = 2 + shift
                    alpha[y * n + x] = 1
                }
            }
        }

        func paint(_ x: Int, _ y: Int, _ l: Float, _ a: Float) {
            guard x >= 0, x < n, y >= 0, y < n else { return }
            level[y * n + x] = l
            alpha[y * n + x] = a
        }

        let bodyLevel = 4 + light * (1 + 0.6 * intensity) + shift  // #D97757, com brilho de #EBA383 na voz
        let bodyAlpha = 0.25 + 0.75 * light
        for (r, row) in rows.enumerated() {
            let chars = Array(row)
            for (c, ch) in chars.enumerated() where ch != "." {
                var l = bodyLevel
                // Olho = onde há "E" no desenho, deslocado pelo "look".
                let src = c - look
                if src >= 0, src < chars.count, chars[src] == "E" { l = 0.5 }
                for dy in 0..<sy { for dx in 0..<sx { paint(ox + c * sx + dx, oy + r * sy + dy, l, bodyAlpha) } }
            }
        }

        // Estrelinha do Pensando acima do mascote.
        if thinking > 0.05 {
            // Pensando gira rápido; Aguardando gira devagar, para dar para diferenciar.
            let frame = time / (state == .aguardando ? 0.35 : 0.12)
            let glyph = spinner[spinnerOrder[Int(frame) % spinnerOrder.count]]
            let gx = n / 2 - 3, gy = oy - 10
            for (r, row) in glyph.enumerated() {
                for (c, ch) in row.enumerated() where ch == "#" {
                    paint(gx + c, gy + r, 5 + shift, thinking)
                }
            }
        }

        var px = [UInt8](repeating: 0, count: n * n * 4)
        for y in 0..<n {
            for x in 0..<n {
                var a = alpha[y * n + x]
                if a <= 0 { continue }
                if y % 6 < 2 { a *= 0.7 }  // scanlines CRT
                let t = bayer[(y % 4) * 4 + x % 4]
                let color = palette[max(0, min(7, Int((level[y * n + x] + t).rounded(.down))))]
                let i = (y * n + x) * 4
                px[i] = UInt8(Float(color.r) * a)
                px[i + 1] = UInt8(Float(color.g) * a)
                px[i + 2] = UInt8(Float(color.b) * a)
                px[i + 3] = UInt8(255 * a)
            }
        }
        return px
    }

    func render() -> CGImage {
        let n = Self.size
        return CGImage(
            width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(pixels()) as CFData)!,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
}
