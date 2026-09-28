import AppKit
import SwiftUI

/// Borderless, click-through panel pinned near the bottom-center of the screen.
/// The panel spans the full screen width so the pill inside can grow and shrink
/// while staying optically centered.
final class OverlayPanel: NSPanel {
    private weak var model: TranscriptModel?

    init(model: TranscriptModel) {
        self.model = model
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let height: CGFloat = 150
        let rect = NSRect(x: screen.minX, y: screen.minY + 120, width: screen.width, height: height)

        super.init(contentRect: rect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Above the character/emoji picker, Spotlight, and every normal window layer.
        level = .screenSaver
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = NSHostingView(rootView: OverlayView(model: model))
    }

    func show() { orderFrontRegardless() }

    /// Let the SwiftUI dismissal animation finish before the window disappears.
    func hide() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [weak self] in
            guard let self, self.model?.isListening != true else { return }
            self.orderOut(nil)
        }
    }
}

struct OverlayView: View {
    @ObservedObject var model: TranscriptModel

    /// How many words stay on screen at once.
    private let windowSize = 5

    private var tokens: [Token] { model.recentTokens(limit: windowSize) }
    private var size: TextSize { model.textSize }

    var body: some View {
        pill
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pill: some View {
        ZStack {
            if tokens.isEmpty {
                idleContent
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            } else {
                wordsContent
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .background(pillBackground)
        .fixedSize()
        // Whole-pill entrance and exit.
        .scaleEffect(model.isListening ? 1.0 : 0.90)
        .opacity(model.isListening ? 1.0 : 0.0)
        .blur(radius: model.isListening ? 0 : 4)
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: model.isListening)
        // Word changes and the idle -> words morph.
        .animation(.spring(response: 0.24, dampingFraction: 0.80), value: tokens.map(\.id))
        .animation(.spring(response: 0.30, dampingFraction: 0.85), value: size)
    }

    private var wordsContent: some View {
        HStack(spacing: size.wordSpacing) {
            ForEach(Array(tokens.enumerated()), id: \.element.id) { position, token in
                Text(token.text)
                    .font(.system(size: size.fontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(token.kind.color)
                    // Older words trail off so the newest word is always brightest.
                    .opacity(fade(at: position))
                    .transition(.asymmetric(
                        insertion: .opacity
                            .combined(with: .offset(y: size.fontSize * 0.34))
                            .combined(with: .scale(scale: 0.82)),
                        removal: .opacity
                            .combined(with: .offset(y: -size.fontSize * 0.42))
                            .combined(with: .scale(scale: 0.90))
                    ))
            }
        }
    }

    private var idleContent: some View {
        HStack(spacing: 9) {
            PulsingDot(size: max(6, size.fontSize * 0.28))
            Text("listening")
                .font(.system(size: size.fontSize * 0.72, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var pillBackground: some View {
        RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
            .fill(Color(white: 0.06).opacity(0.86))
            .overlay(
                RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.20), .white.opacity(0.04)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.8
                    )
            )
            // Tight contact shadow instead of a wide muddy halo.
            .shadow(color: .black.opacity(0.30), radius: 6, y: 2)
    }

    /// Newest word full strength, each older one progressively fainter.
    private func fade(at position: Int) -> Double {
        let stepsFromNewest = Double(tokens.count - 1 - position)
        return max(0.30, 1.0 - stepsFromNewest * 0.18)
    }
}

/// Breathing record indicator, isolated so its repeating animation never
/// interferes with the pill's layout transitions.
private struct PulsingDot: View {
    let size: CGFloat
    @State private var on = false

    var body: some View {
        Circle()
            .fill(Color(red: 1.0, green: 0.32, blue: 0.32))
            .frame(width: size, height: size)
            .opacity(on ? 0.35 : 1.0)
            .scaleEffect(on ? 0.86 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
    }
}
