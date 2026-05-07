import SwiftUI

/// Ambient color field — a slow, nearly-still background motion.
///
/// Three or four very large, very soft, very low-opacity color blobs drift
/// across the canvas on slow Lissajous paths. They overlap additively,
/// which creates subtle breathing in the background color. At a glance the
/// screen looks static; if you watch for 10–15 seconds you notice the wash
/// has shifted.
///
/// Aesthetic: Rothko in motion. A library at night with unseen lamps
/// glowing behind thick curtains. The app is an archive — its background
/// should feel *present*, not *entertaining*.
///
/// Rendered via SwiftUI Canvas + TimelineView(.animation). Periods are long
/// (30-50 seconds per cycle), so the CPU cost is trivial despite running
/// every frame.
struct WavyBackground: View {
    @EnvironmentObject var themeStore: ThemeStore

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas(rendersAsynchronously: true) { ctx, size in
                draw(ctx: ctx, size: size, time: t, palette: themeStore.current)
            }
            .drawingGroup()
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    // MARK: - Drawing

    private func draw(ctx: GraphicsContext, size: CGSize, time: Double, palette: ThemePalette) {
        // Four blobs, each with its own center path, radius, color, and
        // alpha. The path is a Lissajous figure — two independent sinusoids
        // on x and y. Different periods give each blob a unique trajectory
        // so they never align into a simple pattern.
        let blobs: [Blob] = [
            // Lead accent — largest, dead center-ish, slowest.
            Blob(
                periodX: 73, periodY: 89, ampX: 0.22, ampY: 0.28,
                centerX: 0.52, centerY: 0.48,
                radiusFrac: 0.55, color: palette.accent, alpha: 0.22, phase: 0.0
            ),
            // Warm companion — offset to the lower-right, mid size.
            Blob(
                periodX: 61, periodY: 67, ampX: 0.28, ampY: 0.24,
                centerX: 0.68, centerY: 0.62,
                radiusFrac: 0.42, color: palette.humanTint, alpha: 0.18, phase: 2.1
            ),
            // Upper-left counterweight.
            Blob(
                periodX: 83, periodY: 71, ampX: 0.24, ampY: 0.22,
                centerX: 0.28, centerY: 0.32,
                radiusFrac: 0.46, color: palette.accentDim, alpha: 0.20, phase: 4.3
            ),
            // Smallest, most distant — gives the edges some life.
            Blob(
                periodX: 47, periodY: 53, ampX: 0.34, ampY: 0.30,
                centerX: 0.50, centerY: 0.72,
                radiusFrac: 0.32, color: palette.toolTint, alpha: 0.14, phase: 6.7
            ),
        ]

        for blob in blobs {
            draw(blob: blob, ctx: ctx, size: size, time: time)
        }
    }

    private func draw(blob: Blob, ctx: GraphicsContext, size: CGSize, time: Double) {
        let minDim = min(size.width, size.height)
        let radius = minDim * blob.radiusFrac

        // Lissajous drift — each blob's center wanders within an ellipse of
        // amplitude (ampX, ampY) around (centerX, centerY).
        let omegaX = 2.0 * .pi / blob.periodX
        let omegaY = 2.0 * .pi / blob.periodY
        let driftX = CGFloat(sin(time * omegaX + blob.phase)) * blob.ampX * size.width
        let driftY = CGFloat(cos(time * omegaY + blob.phase * 0.7)) * blob.ampY * size.height

        let cx = size.width * blob.centerX + driftX
        let cy = size.height * blob.centerY + driftY

        // Radial gradient: full color at center, transparent at edge.
        // Two-stop with a soft exponential falloff feel via intermediate stop.
        let fill: GraphicsContext.Shading = .radialGradient(
            Gradient(stops: [
                .init(color: blob.color.opacity(blob.alpha),          location: 0.00),
                .init(color: blob.color.opacity(blob.alpha * 0.45),   location: 0.45),
                .init(color: blob.color.opacity(blob.alpha * 0.12),   location: 0.75),
                .init(color: blob.color.opacity(0),                   location: 1.00),
            ]),
            center: CGPoint(x: cx, y: cy),
            startRadius: 0,
            endRadius: radius
        )

        let rect = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
        ctx.fill(Path(ellipseIn: rect), with: fill)
    }
}

// MARK: - Blob description

private struct Blob {
    /// Drift period in seconds. Non-commensurate periods keep blobs from
    /// settling into a visible pattern — they should wander unpredictably.
    let periodX: Double
    let periodY: Double

    /// How far the blob strays from its home (as fraction of canvas size).
    let ampX: CGFloat
    let ampY: CGFloat

    /// Home position (fraction of canvas size).
    let centerX: CGFloat
    let centerY: CGFloat

    /// Blob radius as a fraction of min(width, height).
    let radiusFrac: CGFloat

    let color: Color

    /// Peak alpha at the blob's center. Low — we want ambient wash.
    let alpha: Double

    /// Phase offset so blobs don't share trajectories.
    let phase: Double
}
