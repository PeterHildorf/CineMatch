//
//  VerdictControls.swift
//  CineMatch
//

import SwiftUI

extension Verdict {
    var tint: Color {
        switch self {
        case .notSeen: .gray
        case .horrible: .red
        case .bad: .orange
        case .great: .green
        case .fantastic: .pink
        }
    }
}

/// De fem knapper under Swipe-kortet: fire domme på én række og "Haven't seen" under dem.
struct VerdictButtons: View {
    var isEnabled = true
    let onRate: (Verdict) -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(Verdict.seenOptions) { verdict in
                    Button { onRate(verdict) } label: {
                        VStack(spacing: 4) {
                            Image(systemName: verdict.systemImage)
                                .font(.title2)
                            Text(verdict.label)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .tint(verdict.tint)
                    .accessibilityLabel(verdict.label)
                }
            }
            .buttonStyle(.bordered)

            Button { onRate(.notSeen) } label: {
                Label(Verdict.notSeen.label, systemImage: Verdict.notSeen.systemImage)
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.gray)
        }
        .disabled(!isEnabled)
    }
}

/// "Seen it" → menu med de fire domme. Bruges på anbefalinger og i Search.
struct VerdictMenu: View {
    /// Den nuværende dom (vises i knappen). `nil` = ingen endnu.
    var current: Verdict? = nil
    var title = "Seen it"
    /// Vises kun, når der er en dom, der kan fjernes (Search).
    var onRemove: (() -> Void)? = nil
    var size: ControlSize = .small
    /// Fyldt knap (fx på dagens pick) i stedet for den lyse.
    var isProminent = false
    let onRate: (Verdict) -> Void

    var body: some View {
        if isProminent {
            menu.buttonStyle(.borderedProminent)
        } else {
            menu.buttonStyle(.bordered)
        }
    }

    private var menu: some View {
        Menu {
            // Bedste øverst: menuen åbner tæt på tommelfingeren.
            ForEach(Verdict.seenOptions.reversed()) { verdict in
                Button(verdict.label, systemImage: verdict.systemImage) { onRate(verdict) }
            }
            if let onRemove, current != nil {
                Divider()
                Button("Remove rating", systemImage: "xmark", role: .destructive, action: onRemove)
            }
        } label: {
            if let current, current.isSeen {
                Label(current.label, systemImage: current.systemImage)
                    .foregroundStyle(current.tint)
            } else {
                Label(title, systemImage: "eye")
            }
        }
        .font(.subheadline.weight(.medium))
        .menuStyle(.button)
        .controlSize(size)
    }
}

#Preview {
    VStack(spacing: 30) {
        VerdictButtons { _ in }
        VerdictMenu { _ in }
        VerdictMenu(current: .fantastic, onRemove: {}) { _ in }
    }
    .padding()
}
