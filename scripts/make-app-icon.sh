#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RES_DIR="$ROOT_DIR/Resources"
ICONSET_DIR="$RES_DIR/AppIcon.iconset"
MASTER_PNG="$RES_DIR/AppIcon-1024.png"
ICNS_PATH="$RES_DIR/AppIcon.icns"
SWIFT_SCRIPT="$ROOT_DIR/tmp/render_app_icon.swift"

mkdir -p "$RES_DIR" "$ROOT_DIR/tmp"

cat > "$SWIFT_SCRIPT" <<'SWIFT'
import AppKit
import Foundation

let outPath = CommandLine.arguments[1]
let canvas: CGFloat = 1024
let image = NSImage(size: NSSize(width: canvas, height: canvas))

image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else {
    fatalError("Could not acquire graphics context")
}

ctx.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))
ctx.setAllowsAntialiasing(true)
ctx.setShouldAntialias(true)

let baseRect = CGRect(x: 64, y: 64, width: 896, height: 896)
let basePath = NSBezierPath(roundedRect: baseRect, xRadius: 210, yRadius: 210)

ctx.saveGState()
basePath.addClip()

let bgColors = [
    NSColor(srgbRed: 0.03, green: 0.03, blue: 0.04, alpha: 1).cgColor,
    NSColor(srgbRed: 0.12, green: 0.12, blue: 0.13, alpha: 1).cgColor,
    NSColor(srgbRed: 0.26, green: 0.26, blue: 0.28, alpha: 1).cgColor
] as CFArray
let bgLocations: [CGFloat] = [0.0, 0.58, 1.0]

if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors, locations: bgLocations) {
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 130, y: 942),
        end: CGPoint(x: 900, y: 84),
        options: []
    )
}

if let highlight = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.24).cgColor,
        NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0).cgColor
    ] as CFArray,
    locations: [0.0, 1.0]
) {
    ctx.drawRadialGradient(
        highlight,
        startCenter: CGPoint(x: 298, y: 814),
        startRadius: 0,
        endCenter: CGPoint(x: 298, y: 814),
        endRadius: 560,
        options: []
    )
}

ctx.restoreGState()

basePath.lineWidth = 8
NSColor(calibratedWhite: 1.0, alpha: 0.16).setStroke()
basePath.stroke()

let text = NSMutableAttributedString(string: ".md")
text.addAttributes(
    [
        .font: NSFont.systemFont(ofSize: 390, weight: .black),
        .foregroundColor: NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1),
        .kern: -6
    ],
    range: NSRange(location: 0, length: text.length)
)

let size = text.size()
let textPoint = CGPoint(x: baseRect.midX - size.width / 2, y: baseRect.midY - size.height / 2 + 16)

let textShadow = NSMutableAttributedString(string: ".md")
textShadow.addAttributes(
    [
        .font: NSFont.systemFont(ofSize: 390, weight: .black),
        .foregroundColor: NSColor(calibratedWhite: 0, alpha: 0.34),
        .kern: -6
    ],
    range: NSRange(location: 0, length: textShadow.length)
)
textShadow.draw(at: CGPoint(x: textPoint.x + 2, y: textPoint.y - 8))
text.draw(at: textPoint)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode PNG")
}

try pngData.write(to: URL(fileURLWithPath: outPath))
SWIFT

swift "$SWIFT_SCRIPT" "$MASTER_PNG"

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

sips -z 16 16 "$MASTER_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$MASTER_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$MASTER_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$MASTER_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$MASTER_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$MASTER_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$MASTER_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$MASTER_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$MASTER_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$MASTER_PNG" "$ICONSET_DIR/icon_512x512@2x.png"

iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"

echo "Created:"
echo "$MASTER_PNG"
echo "$ICNS_PATH"
