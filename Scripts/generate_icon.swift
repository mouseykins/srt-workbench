#!/usr/bin/env swift
//
// generate_icon.swift
// Generates a macOS app icon for SRT Workbench.
// Run: swift Scripts/generate_icon.swift
//
import AppKit
import CoreGraphics

let outputDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // Scripts/
    .deletingLastPathComponent() // SRTWorkbench/
    .appendingPathComponent("SRTWorkbench/Resources/Assets.xcassets/AppIcon.appiconset")

// Required macOS icon sizes: (points, scale, filename)
let sizes: [(CGFloat, Int, String)] = [
    (16, 1, "icon_16x16.png"),
    (16, 2, "icon_16x16@2x.png"),
    (32, 1, "icon_32x32.png"),
    (32, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"),
    (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"),
    (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"),
    (512, 2, "icon_512x512@2x.png"),
]

func drawIcon(pixelSize: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: pixelSize, height: pixelSize))
    image.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext
    let s = pixelSize

    // --- Rounded rectangle background ---
    let cornerRadius = s * 0.22
    let inset = s * 0.02
    let bgRect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Gradient: deep navy blue to teal
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 0.08, green: 0.13, blue: 0.28, alpha: 1.0),  // dark navy
            CGColor(red: 0.05, green: 0.30, blue: 0.45, alpha: 1.0),  // teal-blue
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
    ctx.restoreGState()

    // Subtle inner glow at top
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let glowGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.15),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(glowGradient, start: CGPoint(x: s/2, y: s * 0.95), end: CGPoint(x: s/2, y: s * 0.55), options: [])
    ctx.restoreGState()

    // --- Draw waveform bars ---
    let barCount = 9
    let barAreaWidth = s * 0.52
    let barAreaLeft = (s - barAreaWidth) / 2
    let barWidth = barAreaWidth / CGFloat(barCount * 2 - 1)
    let barCenterY = s * 0.52
    let maxBarHeight = s * 0.36

    // Waveform shape: symmetric pattern
    let barHeights: [CGFloat] = [0.25, 0.45, 0.7, 0.9, 1.0, 0.9, 0.7, 0.45, 0.25]

    ctx.saveGState()
    // Teal/cyan color for waveform
    ctx.setFillColor(CGColor(red: 0.2, green: 0.85, blue: 0.85, alpha: 0.95))

    for i in 0..<barCount {
        let h = maxBarHeight * barHeights[i]
        let x = barAreaLeft + CGFloat(i) * barWidth * 2
        let y = barCenterY - h / 2
        let barRect = CGRect(x: x, y: y, width: barWidth, height: h)
        let barPath = CGPath(roundedRect: barRect, cornerWidth: barWidth * 0.4, cornerHeight: barWidth * 0.4, transform: nil)
        ctx.addPath(barPath)
        ctx.fillPath()
    }
    ctx.restoreGState()

    // --- "SRT" text at bottom ---
    if s >= 64 {
        let fontSize = s * 0.13
        let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let textColor = NSColor(calibratedRed: 0.7, green: 0.88, blue: 0.92, alpha: 0.9)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .kern: fontSize * 0.2,
        ]
        let text = "SRT" as NSString
        let textSize = text.size(withAttributes: attrs)
        let textX = (s - textSize.width) / 2
        let textY = s * 0.12
        text.draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)
    }

    image.unlockFocus()
    return image
}

// Generate all sizes
for (points, scale, filename) in sizes {
    let px = points * CGFloat(scale)
    let image = drawIcon(pixelSize: px)

    // Convert to PNG
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        print("ERROR: Failed to generate \(filename)")
        continue
    }

    let fileURL = outputDir.appendingPathComponent(filename)
    do {
        try png.write(to: fileURL)
        print("Created: \(filename) (\(Int(px))x\(Int(px)))")
    } catch {
        print("ERROR writing \(filename): \(error)")
    }
}

// Update Contents.json with filenames
let contentsJSON = """
{
  "images" : [
    {
      "filename" : "icon_16x16.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_16x16@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_32x32.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_32x32@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_128x128.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_128x128@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_256x256.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_256x256@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_512x512.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "filename" : "icon_512x512@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""

let contentsURL = outputDir.appendingPathComponent("Contents.json")
try! contentsJSON.write(to: contentsURL, atomically: true, encoding: .utf8)
print("\nUpdated Contents.json")
print("Done! All icon files generated.")
