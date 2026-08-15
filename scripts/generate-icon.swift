import AppKit

// Generates a 1024x1024 app icon for mmove: a dark rounded-rect tile with a
// minimal white mouse glyph. Run: swift scripts/generate-icon.swift <out.png>

let size: CGFloat = 1024
let outPath = CommandLine.arguments[1]

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("no graphics context") }

// Background: rounded rect tile (macOS icon proportions), subtle dark gradient.
let tileRect = CGRect(x: 64, y: 64, width: size - 128, height: size - 128)
let tilePath = CGPath(roundedRect: tileRect, cornerWidth: 200, cornerHeight: 200, transform: nil)
ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [CGColor(red: 0.26, green: 0.28, blue: 0.33, alpha: 1),
                                   CGColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1)] as CFArray,
                          locations: [0, 1])!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: tileRect.midX, y: tileRect.maxY),
                       end: CGPoint(x: tileRect.midX, y: tileRect.minY),
                       options: [])
ctx.restoreGState()

// Mouse glyph: white filled capsule with a scroll wheel.
let glyphW: CGFloat = 300
let glyphH: CGFloat = 470
let glyphRect = CGRect(x: (size - glyphW) / 2, y: (size - glyphH) / 2, width: glyphW, height: glyphH)
let mousePath = CGPath(roundedRect: glyphRect, cornerWidth: glyphW / 2, cornerHeight: glyphW / 2, transform: nil)
ctx.setFillColor(CGColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1))
ctx.addPath(mousePath)
ctx.fillPath()

// Scroll wheel: dark pill near the top of the glyph.
let wheelW: CGFloat = 44
let wheelH: CGFloat = 110
let wheelRect = CGRect(x: (size - wheelW) / 2, y: glyphRect.maxY - wheelH - 70, width: wheelW, height: wheelH)
let wheelPath = CGPath(roundedRect: wheelRect, cornerWidth: wheelW / 2, cornerHeight: wheelW / 2, transform: nil)
ctx.setFillColor(CGColor(red: 0.16, green: 0.17, blue: 0.21, alpha: 1))
ctx.addPath(wheelPath)
ctx.fillPath()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { fatalError("failed to render PNG") }
try png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
