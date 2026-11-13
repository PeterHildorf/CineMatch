//
//  StarRatingView.swift
//  CineMatch
//

import SwiftUI

/// Fem stjerner, man kan trykke på. Viser kun – selve gemningen sker i ViewModel'en.
struct StarRatingView: View {
    let stars: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    onSelect(value)
                } label: {
                    Image(systemName: value <= stars ? "star.fill" : "star")
                        .foregroundStyle(value <= stars ? .yellow : .secondary)
                        .font(.title3)
                }
                // Uden .plain ville et tryk på én stjerne aktivere hele rækken i en List.
                .buttonStyle(.plain)
            }
        }
        // VoiceOver: én justerbar kontrol i stedet for fem løse knapper.
        .accessibilityElement()
        .accessibilityLabel("Bedømmelse")
        .accessibilityValue(stars == 0 ? "Ikke bedømt" : "\(stars) af 5 stjerner")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSelect(min(stars + 1, 5))
            case .decrement: if stars > 1 { onSelect(stars - 1) }
            @unknown default: break
            }
        }
    }
}

#Preview {
    StarRatingView(stars: 3) { _ in }
}
