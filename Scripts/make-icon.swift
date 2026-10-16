#!/usr/bin/env swift
// Genera l'icona dell'app (PNG 1024x1024) usata da Scripts/build-app.sh.
import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let context = NSGraphicsContext.current!.cgContext
let rect = CGRect(x: 0, y: 0, width: size, height: size)

// Sfondo: rettangolo arrotondato con gradiente blu.
let squircle = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.08, dy: size * 0.08),
                            xRadius: size * 0.2, yRadius: size * 0.2)
squircle.addClip()
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.25, green: 0.55, blue: 1.0, alpha: 1),
    NSColor(calibratedRed: 0.10, green: 0.30, blue: 0.85, alpha: 1)
])!
gradient.draw(in: rect, angle: -90)

// Sagoma del dispositivo.
let phoneWidth = size * 0.34
let phoneHeight = size * 0.56
let phoneRect = CGRect(x: (size - phoneWidth) / 2,
                       y: size * 0.14,
                       width: phoneWidth,
                       height: phoneHeight)
NSColor.white.withAlphaComponent(0.95).setFill()
NSBezierPath(roundedRect: phoneRect, xRadius: size * 0.055, yRadius: size * 0.055).fill()

NSColor(calibratedRed: 0.10, green: 0.30, blue: 0.85, alpha: 1).setFill()
NSBezierPath(roundedRect: phoneRect.insetBy(dx: size * 0.022, dy: size * 0.035),
             xRadius: size * 0.035, yRadius: size * 0.035).fill()

// Freccia di download che entra nel dispositivo.
let arrow = NSBezierPath()
let cx = size / 2
let shaftWidth = size * 0.075
let top = size * 0.82
let headTop = size * 0.56
let tip = size * 0.44
let headHalf = size * 0.145

arrow.move(to: CGPoint(x: cx - shaftWidth / 2, y: top))
arrow.line(to: CGPoint(x: cx + shaftWidth / 2, y: top))
arrow.line(to: CGPoint(x: cx + shaftWidth / 2, y: headTop))
arrow.line(to: CGPoint(x: cx + headHalf, y: headTop))
arrow.line(to: CGPoint(x: cx, y: tip))
arrow.line(to: CGPoint(x: cx - headHalf, y: headTop))
arrow.line(to: CGPoint(x: cx - shaftWidth / 2, y: headTop))
arrow.close()

context.setShadow(offset: CGSize(width: 0, height: -6), blur: 18,
                  color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor.white.setFill()
arrow.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("Impossibile generare il PNG dell'icona\n".data(using: .utf8)!)
    exit(1)
}

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
try! png.write(to: URL(fileURLWithPath: output))
