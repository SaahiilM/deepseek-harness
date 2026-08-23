// Renders the app icon: rounded-rect dark tile, gradient accent bar, "DSH" wordmark.
// Usage: swift make-icon.swift <output.icns>
import AppKit
import CoreGraphics

let size = 1024
guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: swift make-icon.swift <output.icns>\n".data(using: .utf8)!)
    exit(2)
}
let output = CommandLine.arguments[1]

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Background tile with macOS-style margin so the rounded square reads at small sizes.
let inset = CGFloat(100)
let tile = CGRect(x: inset, y: inset, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 2)
let radius = tile.width * 0.225

ctx.setShadow(offset: .zero, blur: 40, color: NSColor(calibratedWhite: 0, alpha: 0.35).cgColor)
NSColor(calibratedRed: 0.043, green: 0.071, blue: 0.125, alpha: 1).setFill()
NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius).fill()
ctx.setShadow(offset: .zero, blur: 0)

// Gradient accent bar across the top of the tile.
let bar = CGRect(x: tile.minX + tile.width * 0.12, y: tile.maxY - tile.height * 0.16,
                 width: tile.width * 0.76, height: tile.height * 0.055)
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
    NSColor(calibratedRed: 0.216, green: 0.494, blue: 0.976, alpha: 1).cgColor,
    NSColor(calibratedRed: 0.420, green: 0.847, blue: 0.960, alpha: 1).cgColor,
] as CFArray, locations: [0, 1])!
ctx.saveGState()
NSBezierPath(roundedRect: bar, xRadius: bar.height / 2, yRadius: bar.height / 2).addClip()
ctx.drawLinearGradient(gradient, start: CGPoint(x: bar.minX, y: bar.midY), end: CGPoint(x: bar.maxX, y: bar.midY), options: [])
ctx.restoreGState()

// Wordmark.
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: tile.width * 0.34, weight: .bold),
    .foregroundColor: NSColor(white: 0.96, alpha: 1),
    .paragraphStyle: paragraph,
]
let label = NSAttributedString(string: "DSH", attributes: attrs)
let bounds = label.boundingRect(with: tile.size, options: [.usesLineFragmentOrigin])
label.draw(at: CGPoint(x: tile.minX, y: tile.midY - bounds.height / 2 + tile.height * 0.02))

image.unlockFocus()

// Export iconset -> icns. iconutil requires the folder name to end in ".iconset".
let workDir = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("dsh-icon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

/// Render the icon at an exact pixel size and return PNG data. NSImage drawing
/// scales the 1024px master into the target rect.
func renderPNG(_ scale: Int) -> Data {
    let out = NSImage(size: NSSize(width: scale, height: scale))
    out.lockFocus()
    image.draw(in: NSRect(x: 0, y: 0, width: scale, height: scale),
               from: CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height),
               operation: .copy, fraction: 1)
    out.unlockFocus()
    let tiff = out.tiffRepresentation!
    let rep = NSBitmapImageRep(data: tiff)!
    return rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:])!
}

// (rendered size, file name in the iconset)
let slots: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]
for (scale, fileName) in slots {
    try renderPNG(scale).write(to: workDir.appendingPathComponent(fileName))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", workDir.path, "-o", output]
try task.run()
task.waitUntilExit()
try? FileManager.default.removeItem(at: workDir)
if task.terminationStatus != 0 {
    FileHandle.standardError.write("iconutil failed\n".data(using: .utf8)!)
    exit(1)
}
