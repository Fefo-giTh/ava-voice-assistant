import AppKit
import XCTest
@testable import Ava

final class BrainTests: XCTestCase {
    private let pb = NSPasteboard(name: .init("ava-test"))

    func testTakesCompleteSentencesAndKeepsTheRest() {
        var buf = "Sua pasta tem doze arquivos. O maior é o vídeo de 3.5 GB e"
        XCTAssertEqual(Brain.takeSpeakable(from: &buf), "Sua pasta tem doze arquivos.")
        XCTAssertEqual(buf, " O maior é o vídeo de 3.5 GB e")
        XCTAssertNil(Brain.takeSpeakable(from: &buf), "não corta no 3.5")
    }

    func testDoesNotCutInsideOpenCopyBlock() {
        var buf = "Deixei o link. <copiar>https://python.org. Outro"
        XCTAssertEqual(Brain.takeSpeakable(from: &buf), "Deixei o link.")
        XCTAssertNil(Brain.takeSpeakable(from: &buf), "<copiar> ainda aberto")
    }

    func testCleanForSpeech() {
        XCTAssertEqual(Brain.cleanForSpeech("Sou a **Ava**. <copiar>x</copiar> Veja https://a.com"), "Sou a Ava.  Veja")
    }

    func testCopyBlocksGoToPasteboard() {
        XCTAssertTrue(Brain.copyBlocks(from: "Pronto. <copiar>https://python.org</copiar>", pasteboard: pb))
        XCTAssertEqual(pb.string(forType: .string), "https://python.org")
        XCTAssertFalse(Brain.copyBlocks(from: "Sem nada para copiar.", pasteboard: pb))
    }

    func testIgnoresWhisperHallucinationsOnNoise() {
        XCTAssertFalse(Conversation.isRealSpeech("Legendas pela comunidade Amara.org"))
        XCTAssertFalse(Conversation.isRealSpeech(" . "))
        XCTAssertTrue(Conversation.isRealSpeech("Que horas são?"))
    }

    /// Com AVA_CLAUDE=1: texto chega em pedaços, personalidade e histórico pelo Claude de verdade.
    func testStreamsIdentityAndRemembers() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["AVA_CLAUDE"] != nil)
        let brain = Brain()
        var pieces = 0
        let name = try await brain.ask("Qual é o seu nome?") { _ in pieces += 1 }
        XCTAssertTrue(name.contains(Config.shared.name), name)
        XCTAssertGreaterThan(pieces, 0, "texto em pedaços")
        _ = try await brain.ask("Meu nome é Marina.") { _ in }
        let start = Date()
        let recall = try await brain.ask("Qual é o meu nome?") { _ in }
        XCTAssertTrue(recall.contains("Marina"), recall)
        print("Ava: 3ª resposta com o claude já aberto em \(String(format: "%.1f", Date().timeIntervalSince(start))) s")
        brain.interrupt()
    }
}
