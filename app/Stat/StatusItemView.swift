import Cocoa
import CoreText
import StatKit

enum StatBlock: String, CaseIterable {
    case cpu = "CPU"
    case gpu = "GPU"
    case temperature = "Temperature"
    case download = "Download"
    case upload = "Upload"
    case weekday = "Weekday"

    var defaultsKey: String { "visible.\(rawValue)" }
}

final class StatusItemView: NSView {
    var stats = Stats() { didSet { updateWidth(); needsDisplay = true } }
    var visibleBlocks = Set(StatBlock.allCases) { didSet { updateWidth(); needsDisplay = true } }

    private var iconCPU: NSImage!
    private var iconGPU: NSImage!
    private var iconTemp: NSImage!
    private var iconDownK: NSImage!
    private var iconDownM: NSImage!
    private var iconUpK: NSImage!
    private var iconUpM: NSImage!
    private var iconDays: [NSImage] = []

    // Layout constants (points)
    // Each block: icon on top (y=1, h=7), number on bottom (y=8)
    // Block height=18, min width=16, gap between blocks=8
    private let blockH: CGFloat = 18
    private let iconY: CGFloat = 1
    private let iconH: CGFloat = 7
    private let numberY: CGFloat = 6
    private let minBlockW: CGFloat = 16
    private let blockGap: CGFloat = 8

    // Menu bar number font; register the bundled font for this process first.
    private let oswaldFont: NSFont = {
        if let url = Bundle.main.url(forResource: "Oswald-Light", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return NSFont(name: "Oswald", size: 11)
            ?? NSFont(name: "Oswald-Light", size: 11)
            ?? .monospacedDigitSystemFont(ofSize: 11, weight: .light)
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        loadResources()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadResources()
    }

    private func loadResources() {
        iconCPU = loadIcon("cpu")
        iconGPU = loadIcon("gpu")
        iconTemp = loadIcon("temp")
        iconDownK = loadIcon("download-k")
        iconDownM = loadIcon("download-m")
        iconUpK = loadIcon("upload-k")
        iconUpM = loadIcon("upload-m")
        iconDays = ["day-sun", "day-mon", "day-tue", "day-wed", "day-thu", "day-fri", "day-sat"].map { loadIcon($0) }
    }

    private func loadIcon(_ name: String) -> NSImage {
        guard let path = Bundle.main.path(forResource: name, ofType: "png"),
              let img = NSImage(contentsOfFile: path) else {
            return NSImage()
        }
        // Scale to exactly 7pt tall (14px @2x), preserve aspect ratio
        let scale = iconH / (img.size.height / 2)
        img.size = NSSize(width: (img.size.width / 2) * scale, height: iconH)
        return img
    }

    private func textWidth(_ text: String) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: oswaldFont]
        return ceil((text as NSString).size(withAttributes: attrs).width)
    }

    private func blockWidth(icon: NSImage, text: String) -> CGFloat {
        let tw = textWidth(text)
        return max(minBlockW, max(icon.size.width, tw))
    }

    private func blocks() -> [(icon: NSImage, text: String)] {
        let dl = stats.downloadDisplay
        let ul = stats.uploadDisplay
        let weekday = Calendar.current.component(.weekday, from: Date())
        let day = Calendar.current.component(.day, from: Date())
        let all: [(block: StatBlock, icon: NSImage, text: String)] = [
            (.cpu, iconCPU, "\(stats.cpuLoad)"),
            (.gpu, iconGPU, "\(stats.gpuLoad)"),
            (.temperature, iconTemp, "\(stats.temperature)"),
            (.download, dl.isMega ? iconDownM : iconDownK, dl.value),
            (.upload, ul.isMega ? iconUpM : iconUpK, ul.value),
            (.weekday, iconDays[weekday - 1], "\(day)"),
        ]
        return all.filter { visibleBlocks.contains($0.block) }.map { ($0.icon, $0.text) }
    }

    private func totalWidth() -> CGFloat {
        let b = blocks()
        if b.isEmpty { return 0 }
        let content = b.map { blockWidth(icon: $0.icon, text: $0.text) }.reduce(0, +)
        return content + blockGap * CGFloat(b.count - 1)
    }

    func updateWidth() {
        let w = totalWidth()
        if abs(frame.width - w) > 0.5 {
            setFrameSize(NSSize(width: w, height: frame.height))
        }
    }

    private var menuBarColor: NSColor {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .black
    }

    override func draw(_ dirtyRect: NSRect) {
        let allBlocks = blocks()
        let color = menuBarColor

        let attrs: [NSAttributedString.Key: Any] = [
            .font: oswaldFont,
            .foregroundColor: color,
        ]

        let topOffset = (bounds.height - blockH) / 2
        var x: CGFloat = 0

        for (i, block) in allBlocks.enumerated() {
            let bw = blockWidth(icon: block.icon, text: block.text)
            let iw = block.icon.size.width

            // Icon: centered horizontally, top-down y=1, height=7
            let iconX = x + (bw - iw) / 2
            let iconDrawY = bounds.height - topOffset - iconY - iconH
            drawTinted(block.icon, in: NSRect(x: iconX, y: iconDrawY, width: iw, height: iconH))

            // Number: left-aligned, top-down y=8
            let textSize = (block.text as NSString).size(withAttributes: attrs)
            let textX = x
            let textDrawY = bounds.height - topOffset - numberY - textSize.height
            (block.text as NSString).draw(at: NSPoint(x: textX, y: textDrawY), withAttributes: attrs)

            x += bw
            if i < allBlocks.count - 1 { x += blockGap }
        }
    }

    private func drawTinted(_ image: NSImage, in rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        menuBarColor.setFill()
        ctx.fill(rect)
        image.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1.0)
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
}
