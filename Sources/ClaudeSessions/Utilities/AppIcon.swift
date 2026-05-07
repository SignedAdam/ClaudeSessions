import AppKit
import CoreGraphics

/// Generates the Dock / app icon programmatically.
/// macOS expects 1024×1024 with ~100px safe margin for the rounded-square silhouette.
///
/// Design: lavender gradient rounded square with a centered "chat + sparkle"
/// glyph — echoing Claude's branding without ripping it off.
enum AppIcon {

    static func makeImage(size: CGFloat = 1024) -> NSImage {
        let pxSize = NSSize(width: size, height: size)
        let image = NSImage(size: pxSize)

        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            draw(in: ctx, size: size)
        }
        image.unlockFocus()
        return image
    }

    private static func draw(in ctx: CGContext, size s: CGFloat) {
        // macOS icon safe area — the rounded square should fill ~80% of canvas
        let margin: CGFloat = s * 0.10
        let rect = CGRect(x: margin, y: margin, width: s - margin * 2, height: s - margin * 2)
        let corner = rect.width * 0.22

        // Path for the rounded square
        let squarePath = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)

        // Background gradient: deep navy -> lavender
        ctx.saveGState()
        ctx.addPath(squarePath)
        ctx.clip()

        let colors = [
            CGColor(red: 0.14, green: 0.13, blue: 0.22, alpha: 1.0),     // top: deep
            CGColor(red: 0.38, green: 0.28, blue: 0.55, alpha: 1.0),     // middle
            CGColor(red: 0.79, green: 0.63, blue: 1.00, alpha: 1.0)      // bottom: lavender
        ] as CFArray
        let locations: [CGFloat] = [0.0, 0.55, 1.0]
        if let space = CGColorSpace(name: CGColorSpace.sRGB),
           let gradient = CGGradient(colorsSpace: space, colors: colors, locations: locations) {
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: rect.midX, y: rect.maxY),
                end: CGPoint(x: rect.midX, y: rect.minY),
                options: []
            )
        }
        ctx.restoreGState()

        // Subtle inner highlight at top
        ctx.saveGState()
        ctx.addPath(squarePath)
        ctx.clip()
        let highlightColors = [
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.18),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.0)
        ] as CFArray
        if let space = CGColorSpace(name: CGColorSpace.sRGB),
           let gradient = CGGradient(colorsSpace: space, colors: highlightColors, locations: [0, 1]) {
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: rect.midX, y: rect.maxY),
                end: CGPoint(x: rect.midX, y: rect.midY),
                options: []
            )
        }
        ctx.restoreGState()

        // Main glyph: a stylized sparkle over a chat bubble
        drawGlyph(in: ctx, bounds: rect)

        // Outer subtle stroke
        ctx.saveGState()
        ctx.addPath(squarePath)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.08))
        ctx.setLineWidth(s * 0.004)
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// Chat bubble with a sparkle — simple, readable at small sizes.
    private static func drawGlyph(in ctx: CGContext, bounds: CGRect) {
        let w = bounds.width
        let h = bounds.height

        // Chat bubble (rounded rect with a tail)
        let bubbleW = w * 0.50
        let bubbleH = h * 0.36
        let bubbleRect = CGRect(
            x: bounds.midX - bubbleW / 2,
            y: bounds.midY - bubbleH / 2 + h * 0.05,
            width: bubbleW,
            height: bubbleH
        )
        let bubblePath = CGMutablePath()
        bubblePath.addRoundedRect(in: bubbleRect, cornerWidth: bubbleH * 0.3, cornerHeight: bubbleH * 0.3)

        // Tail
        let tailX = bubbleRect.minX + bubbleW * 0.22
        let tailY = bubbleRect.minY
        bubblePath.move(to: CGPoint(x: tailX, y: tailY))
        bubblePath.addLine(to: CGPoint(x: tailX - bubbleW * 0.08, y: tailY - bubbleH * 0.25))
        bubblePath.addLine(to: CGPoint(x: tailX + bubbleW * 0.10, y: tailY + bubbleH * 0.08))
        bubblePath.closeSubpath()

        ctx.saveGState()
        ctx.addPath(bubblePath)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
        ctx.fillPath()
        ctx.restoreGState()

        // Sparkle — diamond + small diamonds
        let sparkCenter = CGPoint(x: bubbleRect.midX, y: bubbleRect.midY + h * 0.01)
        drawSparkle(in: ctx, center: sparkCenter, size: bubbleH * 0.42, color: CGColor(red: 0.38, green: 0.28, blue: 0.55, alpha: 1))

        // Small sparkles around
        drawSparkle(in: ctx, center: CGPoint(x: bubbleRect.maxX - bubbleW * 0.18, y: bubbleRect.maxY - bubbleH * 0.25), size: bubbleH * 0.15, color: CGColor(red: 0.5, green: 0.4, blue: 0.75, alpha: 0.7))
        drawSparkle(in: ctx, center: CGPoint(x: bubbleRect.minX + bubbleW * 0.20, y: bubbleRect.maxY - bubbleH * 0.55), size: bubbleH * 0.12, color: CGColor(red: 0.5, green: 0.4, blue: 0.75, alpha: 0.6))
    }

    /// Four-pointed sparkle (diamond-shape).
    private static func drawSparkle(in ctx: CGContext, center: CGPoint, size: CGFloat, color: CGColor) {
        let path = CGMutablePath()
        let r = size / 2
        // Sharp diamond with pinched waists (classic sparkle shape)
        let thin = r * 0.18
        path.move(to: CGPoint(x: center.x, y: center.y + r))
        path.addQuadCurve(to: CGPoint(x: center.x + r, y: center.y), control: CGPoint(x: center.x + thin, y: center.y + thin))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y - r), control: CGPoint(x: center.x + thin, y: center.y - thin))
        path.addQuadCurve(to: CGPoint(x: center.x - r, y: center.y), control: CGPoint(x: center.x - thin, y: center.y - thin))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + r), control: CGPoint(x: center.x - thin, y: center.y + thin))
        path.closeSubpath()

        ctx.saveGState()
        ctx.addPath(path)
        ctx.setFillColor(color)
        ctx.fillPath()
        ctx.restoreGState()
    }
}
