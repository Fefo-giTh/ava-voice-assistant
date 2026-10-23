import KeyboardShortcuts
import XCTest
@testable import Ava

final class ConfigTests: XCTestCase {
    private func decode(_ json: String) throws -> Config {
        try JSONDecoder().decode(Config.self, from: Data(json.utf8))
    }

    func testEmptyConfigUsesDefaults() throws {
        let c = try decode("{}")
        XCTAssertEqual(c.name, "Ava")
        XCTAssertEqual(c.voice, "pm_alex")
        XCTAssertEqual(c.theme.rows, Theme.default.rows)
    }

    func testCustomNameVoicePaletteAndMascot() throws {
        let c = try decode("""
        {"name": "Luna", "voice": "pf_dora",
         "palette": ["#000000","#111111","#222222","#333333","#444444","#D97757","#666666","#FFFFFF"],
         "mascot": {"rows": ["...############...","...##E######E##...",".################.","...############..."],
                    "legs": ["....#.#....#.#....","...#.#......#.#..."]}}
        """)
        XCTAssertEqual(c.name, "Luna")
        XCTAssertEqual(c.voice, "pf_dora")
        XCTAssertEqual(c.theme.palette[5].r, 0xD9)
        XCTAssertEqual(c.theme.rows[2], ".################.")
    }

    func testRejectsBrokenPaletteAndMascot() {
        XCTAssertThrowsError(try decode(##"{"palette": ["#000000"]}"##))
        XCTAssertThrowsError(try decode(###"{"mascot": {"rows": ["##"], "legs": ["#", "#"]}}"###))
    }

    func testParsesHotkeys() {
        XCTAssertEqual(parseHotkey("control+space"), .init(.space, modifiers: .control))
        XCTAssertEqual(parseHotkey("Option + Shift + A"), .init(.a, modifiers: [.option, .shift]))
        XCTAssertNil(parseHotkey("space"), "sem modificador roubaria a tecla de todos os apps")
        XCTAssertNil(parseHotkey("control+?"))
    }
}
