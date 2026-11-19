//
//  Theme.swift
//  CineMatch
//

import SwiftUI

/// CineMatch' udseende samlet ét sted: farver, gradient, hjørner og knapper.
///
/// Accentfarven ligger i `Assets.xcassets/AccentColor` (teal, lysere i mørk tilstand) og sættes som
/// `.tint` på hele appen i `MyApp`. Skift farven dér, så følger knapper, faner, chips og login med.
/// Domme-farverne (rød, orange, gul, grøn, pink) ligger i `Verdict.tint` og er bevidst holdt adskilt.
enum Theme {
    /// Accentfarven fra asset-kataloget.
    static let accent = Color("AccentColor")
    /// Anden farve i gradienten.
    static let accentSecondary = Color(red: 0.18, green: 0.44, blue: 0.89)   // #2F6FE4

    /// Brand-gradienten: plakat-pladsholdere, avatar, login-knap.
    static let gradient = LinearGradient(
        colors: [accent, accentSecondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Hjørner på felter og store knapper.
    static let fieldCornerRadius: CGFloat = 14
    /// Højde på felter og store knapper. Apple anbefaler mindst 44 pt; 56 er behageligt at ramme.
    static let fieldHeight: CGFloat = 56
}

/// Den store fyldte knap (fx "Log ind"): gradient, hvid fed tekst, fuld bredde.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: Theme.fieldHeight)
            .background(Theme.gradient, in: .rect(cornerRadius: Theme.fieldCornerRadius))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}
