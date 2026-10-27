import SwiftUI

enum ChipTone {
    /// Pendiente y cancelado.
    case neutral
    /// En proceso.
    case inProgress
    /// Entregado.
    case success
    /// "Falta precio", "Precio viejo". Lleva triángulo para no depender solo del color.
    case warning

    var background: Color {
        switch self {
        case .neutral: .neutralSoft
        case .inProgress: .accentSoftStrong
        case .success: .successSoft
        case .warning: .warningSoft
        }
    }

    var foreground: Color {
        switch self {
        case .neutral: .inkSecondary
        case .inProgress: .accentTextDeep
        case .success: .successText
        case .warning: .warningText
        }
    }
}

struct Chip: View {
    let text: String
    let tone: ChipTone

    init(_ text: String, tone: ChipTone) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if tone == .warning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            Text(text)
        }
        .font(.footnote.weight(.heavy))
        .foregroundStyle(tone.foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tone.background, in: .capsule)
    }
}

struct StatusChip: View {
    let status: OrderStatus

    var body: some View {
        Chip(status.label, tone: tone)
            .accessibilityLabel("Estado: \(status.label)")
    }

    private var tone: ChipTone {
        switch status {
        case .pending, .cancelled: .neutral
        case .inProgress: .inProgress
        case .delivered: .success
        }
    }
}
