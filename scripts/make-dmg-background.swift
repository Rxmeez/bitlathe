// release: draws the DMG background. Usage: swift make-dmg-background.swift out.png width height scale
import AppKit
let a = CommandLine.arguments
let w = Int(a[2])!, h = Int(a[3])!, s = Int(a[4])!
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w * s, pixelsHigh: h * s, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: w, height: h)   // points; pixel density comes from the scale
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGradient(starting: NSColor(calibratedRed: 0.97, green: 0.97, blue: 0.98, alpha: 1),
           ending: NSColor(calibratedRed: 0.88, green: 0.89, blue: 0.93, alpha: 1))!.draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: -90)
let title = NSAttributedString(string: "Drag Bitlathe to Applications", attributes: [
    .font: NSFont.systemFont(ofSize: 20, weight: .semibold), .foregroundColor: NSColor(calibratedWhite: 0.25, alpha: 1)])
title.draw(at: NSPoint(x: (CGFloat(w) - title.size().width) / 2, y: 330))
// Arrow between the app icon (x=180) and the Applications link (x=480), at icon height (y=190 from top).
let y = CGFloat(h) - 190
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 250, y: y)); arrow.line(to: NSPoint(x: 405, y: y))
arrow.move(to: NSPoint(x: 390, y: y + 12)); arrow.line(to: NSPoint(x: 408, y: y)); arrow.line(to: NSPoint(x: 390, y: y - 12))
arrow.lineWidth = 4; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
NSColor(calibratedWhite: 0.55, alpha: 1).setStroke(); arrow.stroke()
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[1]))
