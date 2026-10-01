#!/usr/bin/env swift
// Export the two-rectangle website SVG into macOS icon slots. Development only.
import Foundation
import CoreGraphics
import ImageIO

final class IconSource: NSObject, XMLParserDelegate {
    var rectangles: [[String: String]] = []
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if name == "svg" { precondition(attributes["viewBox"] == "0 0 32 32") }
        else { precondition(name == "rect"); rectangles.append(attributes) }
    }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = IconSource()
let parser = XMLParser(data: try Data(contentsOf: root.appendingPathComponent("Resources/AppIcon.svg")))
parser.delegate = source
precondition(parser.parse() && source.rectangles.count == 2, "Expected the website's two-rectangle icon.")
let catalog = root.appendingPathComponent("Resources/Assets.xcassets")
let icons = catalog.appendingPathComponent("AppIcon.appiconset")
try FileManager.default.createDirectory(at: icons, withIntermediateDirectories: true)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func render(size: Int, to url: URL) throws {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Preserve the exact website mark inside the usual macOS transparent margin.
    let inset = CGFloat(size) * 0.08
    let scale = CGFloat(size) * 0.84 / 32
    context.translateBy(x: inset, y: CGFloat(size) - inset)
    context.scaleBy(x: scale, y: -scale)
    for attributes in source.rectangles {
        func number(_ name: String) -> CGFloat { CGFloat(Double(attributes[name] ?? "0")!) }
        let rect = CGRect(x: number("x"), y: number("y"), width: number("width"), height: number("height"))
        let rgb = UInt32(attributes["fill"]!.dropFirst(), radix: 16)!
        let components = [CGFloat((rgb >> 16) & 255) / 255, CGFloat((rgb >> 8) & 255) / 255, CGFloat(rgb & 255) / 255, 1]
        context.setFillColor(CGColor(colorSpace: space, components: components)!)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: number("rx"), cornerHeight: number("rx"), transform: nil))
        context.fillPath()
    }
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination))
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(size: points * scale, to: icons.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let info: [String: Any] = ["author": "xcode", "version": 1]
try JSONSerialization.data(withJSONObject: ["info": info], options: [.prettyPrinted, .sortedKeys])
    .write(to: catalog.appendingPathComponent("Contents.json"))
try JSONSerialization.data(withJSONObject: ["images": images, "info": info], options: [.prettyPrinted, .sortedKeys])
    .write(to: icons.appendingPathComponent("Contents.json"))
print("Generated 10 macOS icon slots from Resources/AppIcon.svg.")
