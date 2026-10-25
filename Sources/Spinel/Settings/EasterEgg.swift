import AppKit
import AVFoundation
import SwiftUI
import WebKit

/// Click "Spinel" on the About page five times: the interface falls apart under gravity, then
/// Spinel sings "Other Friends" (0:56–1:37). Back, or the end of the clip, puts everything back.
@MainActor
@Observable
final class EasterEgg {
    enum Phase { case idle, falling, video }

    struct Transform: Equatable {
        var offset: CGSize
        var angle: Double
    }

    static let space = "spinel.window"
    /// The clip, downloaded locally. It isn't shipped in the repo or releases (it's Cartoon
    /// Network's), so builds without it fall back to YouTube.
    static let clip = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Spinel/other-friends.mp4")

    private(set) var phase: Phase = .idle
    private(set) var transforms: [String: Transform] = [:]

    /// Frames of everything marked `.fallable`, in the window's coordinate space.
    @ObservationIgnored var frames: [String: CGRect] = [:]
    @ObservationIgnored private var bodies: [Body] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var elapsed = 0.0
    @ObservationIgnored private var floor = 0.0
    @ObservationIgnored private var taps: [Date] = []

    func tap() {
        let now = Date()
        taps = taps.filter { now.timeIntervalSince($0) < 2 } + [now]
        if taps.count >= 5 {
            taps = []
            start()
        }
    }

    private func start() {
        guard phase == .idle, !frames.isEmpty else { return }
        floor = Double(NSApp.keyWindow?.contentView?.bounds.height ?? 900)
        // Top elements let go first so they land on the ones below before those drop too.
        bodies = frames.sorted { $0.value.minY < $1.value.minY }.enumerated().map { index, entry in
            Body(
                id: entry.key,
                home: entry.value,
                center: CGPoint(x: entry.value.midX, y: entry.value.midY),
                velocity: CGVector(dx: .random(in: -90...90), dy: .random(in: -260...(-60))),
                angle: 0,
                spin: .random(in: -2.5...2.5) * Self.spinScale(entry.value.size),
                releaseAt: Double(index) * 0.07 + .random(in: 0...0.12)
            )
        }
        elapsed = 0
        phase = .falling
        let timer = Timer(timeInterval: 1 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step(1 / 120) }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func reset() {
        timer?.invalidate()
        timer = nil
        withAnimation(.spring(duration: 0.8, bounce: 0.25)) {
            phase = .idle
            transforms = [:]
        }
    }

    // MARK: - Physics

    private struct Body {
        let id: String
        let home: CGRect
        var center: CGPoint
        var velocity: CGVector
        var angle: Double
        var spin: Double
        let releaseAt: Double
    }

    /// Big pieces turn slowly, like heavier objects would.
    private static func spinScale(_ size: CGSize) -> Double {
        min(1, 140 / max(size.width, size.height, 1))
    }

    private func step(_ dt: Double) {
        elapsed += dt
        for i in bodies.indices where elapsed >= bodies[i].releaseAt {
            bodies[i].velocity.dy += 2400 * dt
            bodies[i].center.x += bodies[i].velocity.dx * dt
            bodies[i].center.y += bodies[i].velocity.dy * dt
            bodies[i].angle += bodies[i].spin * dt
        }
        collide()
        transforms = Dictionary(uniqueKeysWithValues: bodies.map { body in
            (body.id, Transform(
                offset: CGSize(width: body.center.x - body.home.midX, height: body.center.y - body.home.midY),
                angle: body.angle
            ))
        })
        let gone = bodies.allSatisfy { $0.center.y - $0.home.height / 2 > floor + 40 }
        if gone || elapsed > 8 {
            timer?.invalidate()
            timer = nil
            withAnimation(.easeOut(duration: 0.4)) { phase = .video }
        }
    }

    /// Box-against-box collisions (rotation is cosmetic). Bodies that haven't let go yet are
    /// immovable, so falling pieces bounce off and pile onto them.
    private func collide() {
        let restitution = 0.35
        for i in bodies.indices {
            for j in bodies.indices where j > i {
                let aMoving = elapsed >= bodies[i].releaseAt
                let bMoving = elapsed >= bodies[j].releaseAt
                guard aMoving || bMoving else { continue }
                let a = bodies[i], b = bodies[j]
                let dx = b.center.x - a.center.x
                let dy = b.center.y - a.center.y
                let overlapX = (a.home.width + b.home.width) / 2 * 0.92 - abs(dx)
                let overlapY = (a.home.height + b.home.height) / 2 * 0.92 - abs(dy)
                guard overlapX > 0, overlapY > 0 else { continue }

                let alongX = overlapX < overlapY
                let sign: Double = (alongX ? dx : dy) >= 0 ? 1 : -1
                let depth = alongX ? overlapX : overlapY
                let share = aMoving && bMoving ? 0.5 : 1
                let relative = alongX ? b.velocity.dx - a.velocity.dx : b.velocity.dy - a.velocity.dy
                let impulse = relative * sign < 0 ? -(1 + restitution) * relative * share : 0

                if aMoving {
                    if alongX { bodies[i].center.x -= sign * depth * share } else { bodies[i].center.y -= sign * depth * share }
                    if alongX { bodies[i].velocity.dx -= impulse } else { bodies[i].velocity.dy -= impulse }
                    bodies[i].spin += .random(in: -1.5...1.5) * Self.spinScale(a.home.size)
                }
                if bMoving {
                    if alongX { bodies[j].center.x += sign * depth * share } else { bodies[j].center.y += sign * depth * share }
                    if alongX { bodies[j].velocity.dx += impulse } else { bodies[j].velocity.dy += impulse }
                    bodies[j].spin += .random(in: -1.5...1.5) * Self.spinScale(b.home.size)
                }
            }
        }
    }
}

// MARK: - Marking views that fall

struct FallableFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Lets the easter egg knock this view down. Mark leaf elements only; nested ones would overlap.
    func fallable(_ id: String) -> some View { modifier(Fallable(id: id)) }
}

private struct Fallable: ViewModifier {
    let id: String
    @Environment(EasterEgg.self) private var egg

    func body(content: Content) -> some View {
        let transform = egg.transforms[id]
        content
            .background(GeometryReader { geometry in
                Color.clear.preference(key: FallableFrames.self, value: [id: geometry.frame(in: .named(EasterEgg.space))])
            })
            .rotationEffect(.radians(transform?.angle ?? 0))
            .offset(transform?.offset ?? .zero)
            .zIndex(transform == nil ? 0 : 1)
    }
}

// MARK: - Video

struct EasterEggVideo: View {
    let egg: EasterEgg

    var body: some View {
        ZStack(alignment: .topLeading) {
            Brand.black
            if FileManager.default.fileExists(atPath: EasterEgg.clip.path) {
                LocalClip(url: EasterEgg.clip, onEnd: { egg.reset() })
            } else {
                YouTubeClip(onEnd: { egg.reset() })
            }
            Button { egg.reset() } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .glassButton()
            .background(Brand.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.top, 40)
            .padding(.leading, 20)
        }
        .ignoresSafeArea()
    }
}

/// Plays the downloaded clip edge to edge, cropping to fill whatever size the window is.
private struct LocalClip: NSViewRepresentable {
    let url: URL
    let onEnd: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PlayerView {
        let view = PlayerView()
        let player = AVPlayer(url: url)
        view.playerLayer.player = player
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main
        ) { _ in MainActor.assumeIsolated { onEnd() } }
        player.play()
        return view
    }

    func updateNSView(_ view: PlayerView, context: Context) {}

    static func dismantleNSView(_ view: PlayerView, coordinator: Coordinator) {
        view.playerLayer.player?.pause()
        view.playerLayer.player = nil
        if let observer = coordinator.observer { NotificationCenter.default.removeObserver(observer) }
    }

    final class Coordinator {
        var observer: NSObjectProtocol?
    }

    final class PlayerView: NSView {
        let playerLayer = AVPlayerLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            playerLayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(playerLayer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            CATransaction.commit()
        }
    }
}

/// Plays the clip through YouTube's IFrame API and reports when it reaches its end time.
private struct YouTubeClip: NSViewRepresentable {
    let onEnd: () -> Void

    private static let html = """
    <!doctype html>
    <html><head><meta name="referrer" content="strict-origin-when-cross-origin">
    <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}#player{width:100%;height:100%}</style>
    </head><body><div id="player"></div>
    <script src="https://www.youtube.com/iframe_api"></script>
    <script>
    function onYouTubeIframeAPIReady() {
      new YT.Player('player', {
        videoId: 'UIPG-OCSRBU',
        playerVars: { start: 56, end: 97, autoplay: 1, controls: 0, disablekb: 1, rel: 0, iv_load_policy: 3, playsinline: 1 },
        events: { onStateChange: function (e) { if (e.data === 0) window.webkit.messageHandlers.egg.postMessage('ended'); } }
      });
    }
    </script></body></html>
    """

    func makeCoordinator() -> Coordinator { Coordinator(onEnd: onEnd) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(context.coordinator, name: "egg")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        // YouTube refuses embeds without a referring origin, so give the page one.
        view.loadHTMLString(Self.html, baseURL: URL(string: "https://pzmuv1517.github.io/Spinel/"))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {}

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "egg")
        view.loadHTMLString("", baseURL: nil)  // stop the audio
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let onEnd: () -> Void
        init(onEnd: @escaping () -> Void) { self.onEnd = onEnd }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            onEnd()
        }
    }
}
