//
//  AppLogView.swift
//  CineMatch
//

import SwiftUI
import UIKit

/// Knap til fejlskærmene: åbner appens log, så fejlen kan kopieres eller sendes videre.
struct ShowLogButton: View {
    @State private var isShowingLog = false

    var body: some View {
        Button("Show log", systemImage: "doc.text.magnifyingglass") {
            isShowingLog = true
        }
        .sheet(isPresented: $isShowingLog) {
            NavigationStack { AppLogView() }
        }
    }
}

/// Lille rød fejlbesked med et log-ikon ved siden af. Bruges overalt, hvor en handling kan fejle.
struct InlineError: View {
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
            Spacer(minLength: 8)
            ShowLogButton()
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .font(.footnote)
        }
    }
}

/// Hele loggen som markerbar tekst med "Copy" og "Share".
struct AppLogView: View {
    /// Øjebliksbillede, taget da skærmen åbnede.
    @State private var report: String
    @State private var didCopy = false
    @Environment(\.dismiss) private var dismiss
    private let log: AppLog

    init(log: AppLog = .shared) {
        self.log = log
        _report = State(initialValue: log.report())
    }

    var body: some View {
        ScrollView {
            Text(report)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.string = report
                    didCopy = true
                }
                ShareLink(item: report)
            }
        }
    }
}

#Preview {
    let log = AppLog()
    log.info("Supabase configured")
    log.error("allSignals failed", URLError(.notConnectedToInternet))
    return NavigationStack { AppLogView(log: log) }
}
