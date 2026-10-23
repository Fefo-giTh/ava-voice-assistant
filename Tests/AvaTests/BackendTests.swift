import AVFoundation
import XCTest
@testable import Ava

final class BackendTests: XCTestCase {
    func testWavHeader() {
        let d = Backend.wav([0, 0.5, -0.5, 1], sampleRate: 16000)
        XCTAssertEqual(d.count, 44 + 8)
        XCTAssertEqual(String(decoding: d.prefix(4), as: UTF8.self), "RIFF")
    }

    /// Ida e volta pelo servidor: sintetiza, regrava com nosso WAV e transcreve. Rode com AVA_SERVER=1 e o servidor da Ava ligado.
    func testRoundTripThroughServer() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["AVA_SERVER"] != nil)
        let audio = try await Backend.synthesize("Bom dia, qual é a previsão do tempo?", voice: "pf_dora")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ava-test.wav")
        try audio.write(to: url)
        let file = try AVAudioFile(forReading: url)
        let buf = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buf)
        let samples = Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))
        let text = try await Backend.transcribe(Backend.wav(samples, sampleRate: Int(file.processingFormat.sampleRate)))
        XCTAssertTrue(text.lowercased().contains("previsão"), "transcreveu: \(text)")
    }
}
