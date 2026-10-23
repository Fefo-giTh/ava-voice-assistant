import AppKit

/// Janela flutuante 132×132 que mostra a esfera ampliada 3× sem suavização.
final class OrbPanel: NSPanel {
    let renderer = OrbRenderer()
    private let imageLayer = CALayer()
    private var displayLink: CADisplayLink?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 132, height: 132),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        ignoresMouseEvents = true

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 132, height: 132))
        view.wantsLayer = true
        imageLayer.frame = view.bounds
        imageLayer.magnificationFilter = .nearest
        imageLayer.actions = ["contents": NSNull()]  // sem fade implícito entre frames
        view.layer?.addSublayer(imageLayer)
        contentView = view

        if !setFrameUsingName("AvaOrb"), let s = NSScreen.main?.visibleFrame {
            setFrameOrigin(NSPoint(x: s.maxX - 132 - 16, y: s.minY + 16))
        }
        setFrameAutosaveName("AvaOrb")  // o macOS salva a posição a cada arrasto

        displayLink = view.displayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func tick(_ link: CADisplayLink) {
        renderer.step(dt: Float(link.targetTimestamp - link.timestamp))
        // A esfera só aparece fora do Repouso. Fica transparente em vez de fechar a janela,
        // porque o displayLink para quando a janela sai da tela.
        let resting = renderer.state == .repouso
        let hidden = resting && renderer.light < 0.02
        alphaValue = hidden ? 0 : 1
        ignoresMouseEvents = resting
        if !hidden { imageLayer.contents = renderer.render() }
    }
}
