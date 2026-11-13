//
//  StarRatingControl.swift
//  CineMatch
//

import SwiftUI

/// Fem stjerner med halve trin. Tryk på venstre halvdel af en stjerne giver ½.
/// Kalder `onRate` med det samme (som Letterboxd) – "Undo" retter et forkert tryk.
struct StarRatingControl: View {
    /// Den viste værdi (0 = ingen stjerner).
    var value: Double = 0
    var starSize: CGFloat = 34
    let onRate: (Double) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: symbol(for: star))
                    .font(.system(size: starSize * 0.8))
                    .foregroundStyle(Double(star) - 0.5 <= value ? Color.yellow : Color.secondary)
                    .frame(width: starSize, height: starSize)
                    .contentShape(.rect)
                    .onTapGesture(coordinateSpace: .local) { location in
                        let half = location.x < starSize / 2
                        onRate(Double(star) - (half ? 0.5 : 0))
                    }
            }
        }
        // VoiceOver: én justerbar kontrol. Op/ned ændrer et halvt trin, dobbelttryk gemmer.
        .accessibilityElement()
        .accessibilityLabel("Rate with stars")
        .accessibilityValue(value == 0 ? "Not rated" : "\(value.formatted()) of 5 stars")
        .accessibilityHint("Swipe up or down to choose, then double-tap to save.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: pending = min((pending == 0 ? value : pending) + 0.5, 5)
            case .decrement: pending = max((pending == 0 ? value : pending) - 0.5, 0.5)
            @unknown default: break
            }
        }
        .accessibilityAction { if pending > 0 { onRate(pending) } }
    }

    /// Kun til VoiceOver: værdien, før den gemmes.
    @State private var pending: Double = 0

    private func symbol(for star: Int) -> String {
        let star = Double(star)
        if value >= star { return "star.fill" }
        if value >= star - 0.5 { return "star.leadinghalf.filled" }
        return "star"
    }
}

#Preview {
    StarRatingControl(value: 3.5) { _ in }
}
