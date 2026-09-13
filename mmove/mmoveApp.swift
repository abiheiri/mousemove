import SwiftUI

@main
struct MMoveApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var engine: JiggleEngine

    init() {
        let store = SettingsStore()
        let engine = JiggleEngine(settings: store)
        _settings = StateObject(wrappedValue: store)
        _engine = StateObject(wrappedValue: engine)
        engine.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(settings: settings, engine: engine)
        } label: {
            if let countdown = engine.countdownText {
                Image(nsImage: Self.menuBarImage(text: countdown))
            } else if settings.isEnabled {
                Image(nsImage: Self.menuBarImage(text: "On"))
            } else {
                Image(systemName: "computermouse")
            }
        }
        .menuBarExtraStyle(.menu)
    }

    /// MenuBarExtra renders only one label element — a Label shows its icon
    /// and drops its title, an inline symbol in Text drops the image, and an
    /// HStack drops the text. Compositing icon + text into a single template
    /// image is the reliable way to show both.
    static func menuBarImage(text: String) -> NSImage {
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let symbol = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "mmove")!
            .withSymbolConfiguration(symbolConfig)!
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let gap: CGFloat = 4
        let height: CGFloat = 18
        let symbolSize = symbol.size
        let width = symbolSize.width + gap + textSize.width
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            let symbolY = (height - symbolSize.height) / 2
            symbol.draw(in: NSRect(x: 0, y: symbolY, width: symbolSize.width, height: symbolSize.height))
            let textY = (height - textSize.height) / 2
            (text as NSString).draw(at: NSPoint(x: symbolSize.width + gap, y: textY), withAttributes: attrs)
            return true
        }
        image.isTemplate = true
        return image
    }
}
