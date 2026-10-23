import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Ava

final class OrbRendererTests: XCTestCase {
    private func settle(_ r: OrbRenderer, _ s: OrbState, amplitude: Float = 0.8) {
        r.state = s
        r.amplitude = amplitude
        for _ in 0..<240 { r.step() }
    }

    private func alpha(_ px: [UInt8], _ x: Int, _ y: Int) -> UInt8 { px[(y * OrbRenderer.size + x) * 4 + 3] }
    private func red(_ px: [UInt8], _ x: Int, _ y: Int) -> UInt8 { px[(y * OrbRenderer.size + x) * 4] }

    func testRepousoIsOnlyAFaintMascot() {
        let r = OrbRenderer(theme: .default)
        settle(r, .repouso)
        let px = r.pixels()
        XCTAssertEqual(Int(alpha(px, 22, 26)), 64, accuracy: 2, "corpo do mascote fraco (25%)")
        XCTAssertEqual(alpha(px, 22, 2), 0, "sem estrelinha nem halo")
    }

    func testPensandoShowsSpinnerAboveMascot() {
        let r = OrbRenderer(theme: .default)
        settle(r, .pensando)
        let px = r.pixels()
        let spinnerArea = (4..<20).flatMap { y in (15..<29).map { x in alpha(px, x, y) } }
        XCTAssertTrue(spinnerArea.contains { $0 > 200 }, "estrelinha visível acima do mascote")
    }

    func testEyesAreDarkerThanBody() {
        let r = OrbRenderer(theme: .default)
        settle(r, .ouvindo, amplitude: 0)
        let px = r.pixels()
        // Linha dos olhos: sprite linha 1 → y = 18 + 4...7; olho na coluna 5 → x = 4 + 10.
        XCTAssertLessThan(red(px, 14, 23), red(px, 18, 23))
    }

    func testErroReturnsToRepouso() {
        let r = OrbRenderer(theme: .default)
        r.state = .erro
        for _ in 0..<70 { r.step() }
        XCTAssertEqual(r.state, .repouso)
    }

    /// Com AVA_SNAPSHOT_DIR definido, salva um PNG de cada estado para inspeção visual.
    func testSnapshots() throws {
        guard let dir = ProcessInfo.processInfo.environment["AVA_SNAPSHOT_DIR"] else { return }
        for s in OrbState.allCases where s != .erro {
            let r = OrbRenderer(theme: .default)
            settle(r, s)
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(s.rawValue).png")
            let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(dest, r.render(), nil)
            XCTAssertTrue(CGImageDestinationFinalize(dest))
        }
    }
}
