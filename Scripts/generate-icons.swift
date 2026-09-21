import AppKit
import Foundation

// Regenerates every rasterised icon from the same geometry the layered AppIcon.icon
// uses, so the two can never drift apart.
//
// Two outputs:
//   * Assets.xcassets/AppIcon.appiconset — the fallback for macOS 14-25, which predate
//     the layered .icon format
//   * Assets.xcassets/MenuBarIcon.imageset — a template glyph, alpha only. Template
//     images ignore colour entirely, so this is drawn in flat black and macOS tints it
//     for light, dark and the accent-coloured menu bar.

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let assets = root.appending(path: "TabSwitcher/Assets.xcassets")

func context(_ side: Int) -> CGContext {
    CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// The app icon, drawn at any size. Unlike the .icon bundle this bakes in the squircle
/// mask and the gradient, because nothing composites it for us on older systems.
func drawAppIcon(_ ctx: CGContext, side: CGFloat) {
    let unit = side / 1024
    ctx.saveGState()
    ctx.addPath(rounded(CGRect(x: 0, y: 0, width: side, height: side), side * 0.2237))
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [NSColor(srgbRed: 0.451, green: 0.380, blue: 0.969, alpha: 1).cgColor,
                 NSColor(srgbRed: 0.239, green: 0.169, blue: 0.659, alpha: 1).cgColor] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: side), end: .zero, options: [])

    // Same coordinates as the SVG layers, in CoreGraphics' bottom-left origin.
    func tile(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, _ alpha: CGFloat) {
        ctx.setFillColor(NSColor.white.withAlphaComponent(alpha).cgColor)
        ctx.addPath(rounded(CGRect(x: x * unit, y: y * unit, width: w * unit, height: h * unit), r * unit))
        ctx.fillPath()
    }
    tile(160, 248, 320, 232, 44, 0.26)
    tile(544, 248, 320, 232, 44, 0.26)
    tile(544, 544, 320, 232, 44, 0.26)
    tile(133, 517, 374, 286, 52, 1.0)
    ctx.restoreGState()
}

/// The menu bar glyph. Simplified hard: at 18pt the full four-pane grid turns to mush,
/// so this is three panes with the chosen one solid and the others outlined.
func drawMenuBarIcon(_ ctx: CGContext, side: CGFloat) {
    let unit = side / 36
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.setStrokeColor(NSColor.black.cgColor)
    ctx.setLineWidth(2.6 * unit)

    // Two outlined panes behind.
    for (x, y) in [(19.0, 19.0), (19.0, 4.0)] {
        ctx.addPath(rounded(CGRect(x: x * unit, y: y * unit, width: 13 * unit, height: 13 * unit),
                            3.2 * unit))
        ctx.strokePath()
    }
    ctx.addPath(rounded(CGRect(x: 4 * unit, y: 4 * unit, width: 13 * unit, height: 13 * unit),
                        3.2 * unit))
    ctx.strokePath()
    // The chosen pane, filled.
    ctx.addPath(rounded(CGRect(x: 3 * unit, y: 18 * unit, width: 15 * unit, height: 15 * unit),
                        3.6 * unit))
    ctx.fillPath()
}

func write(_ ctx: CGContext, to url: URL) throws {
    let data = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        .representation(using: .png, properties: [:])!
    try data.write(to: url)
}

// MARK: - App icon set

let appIconSet = assets.appending(path: "AppIcon.appiconset")
try FileManager.default.createDirectory(at: appIconSet, withIntermediateDirectories: true)

let entries: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                             (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
for (points, scale) in entries {
    let pixels = points * scale
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    let ctx = context(pixels)
    drawAppIcon(ctx, side: CGFloat(pixels))
    try write(ctx, to: appIconSet.appending(path: name))
    images.append([
        "size": "\(points)x\(points)", "idiom": "mac",
        "filename": name, "scale": "\(scale)x",
    ])
}
let appIconJSON: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try JSONSerialization.data(withJSONObject: appIconJSON, options: [.prettyPrinted, .sortedKeys])
    .write(to: appIconSet.appending(path: "Contents.json"))

// MARK: - Menu bar glyph

let menuBarSet = assets.appending(path: "MenuBarIcon.imageset")
try FileManager.default.createDirectory(at: menuBarSet, withIntermediateDirectories: true)
var menuImages: [[String: String]] = []
for scale in 1...2 {
    let pixels = 18 * scale
    let name = "menubar\(scale == 2 ? "@2x" : "").png"
    let ctx = context(pixels)
    drawMenuBarIcon(ctx, side: CGFloat(pixels))
    try write(ctx, to: menuBarSet.appending(path: name))
    menuImages.append(["idiom": "mac", "filename": name, "scale": "\(scale)x"])
}
let menuBarJSON: [String: Any] = [
    "images": menuImages,
    "info": ["version": 1, "author": "xcode"],
    // Rendered as a template so macOS owns the colour — required for the menu bar to
    // adapt to light, dark, and accent tinting.
    "properties": ["template-rendering-intent": "template"],
]
try JSONSerialization.data(withJSONObject: menuBarJSON, options: [.prettyPrinted, .sortedKeys])
    .write(to: menuBarSet.appending(path: "Contents.json"))

// The asset catalog itself.
try? FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
try JSONSerialization.data(
    withJSONObject: ["info": ["version": 1, "author": "xcode"]],
    options: [.prettyPrinted, .sortedKeys]
).write(to: assets.appending(path: "Contents.json"))

print("wrote \(entries.count) app icon sizes and 2 menu bar sizes")
