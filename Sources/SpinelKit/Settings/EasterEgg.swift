import AppKit
import QuarryKit
import SwiftUI
import WebKit

/// Spinel's easter egg: click "Spinel" on the About page five times and the window falls apart
/// (QuarryKit's `easterEggStage`), then Spinel sings "Other Friends" (0:56–1:37).
@MainActor
enum SpinelEasterEgg {
    /// The clip, downloaded locally. It isn't shipped in the repo or releases (it's Cartoon
    /// Network's), so builds without it fall back to YouTube.
    static let clip = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Spinel/other-friends.mp4")

    @ViewBuilder
    static func finale(_ done: @escaping () -> Void) -> some View {
        if FileManager.default.fileExists(atPath: clip.path) {
            EasterEggClip(url: clip, onEnd: done)
        } else {
            YouTubeClip(onEnd: done)
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
