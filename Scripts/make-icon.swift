// Renders Resources/AppIcon.icns from the same SF Symbol the app draws at
// runtime, so the Finder icon, the Login Items icon and the Control Center
// artwork cannot drift apart.
//
// Run with `just icon`. The .icns is committed because the app target needs it
// at build time and CI should not depend on this script.
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let iconset = URL(fileURLWithPath: "build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data {
    let size = CGSize(width: pixels, height: pixels)
    let image = NSImage(size: size)
    image.lockFocus()
    let configuration = NSImage.SymbolConfiguration(
        pointSize: CGFloat(pixels) * 0.62,
        weight: .medium
    )
    .applying(NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
    if let note = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) {
        let s = note.size
        note.draw(
            in: NSRect(
                x: (size.width - s.width) / 2,
                y: (size.height - s.height) / 2,
                width: s.width,
                height: s.height
            )
        )
    }
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    rep.size = size
    return rep.representation(using: .png, properties: [:])!
}

for size in sizes {
    let data = render(size)
    try data.write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    if size <= 512 {
        let retina = render(size * 2)
        try retina.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
    }
}
print("wrote \(iconset.path)")
