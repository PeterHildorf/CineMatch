//
//  StreamingServicesView.swift
//  CineMatch
//

import SwiftUI

/// Liste over streamingtjenester med flueben. Vises som sheet.
struct StreamingServicesView: View {
    let viewModel: StreamingServicesViewModel
    /// Kaldes, når valget er gemt (fx så For You kan opdatere).
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(viewModel.services) { service in
                        ServiceRow(service: service, isSelected: viewModel.isSelected(service)) {
                            viewModel.toggle(service)
                        }
                    }
                } header: {
                    Text("We always show the service you already pay for first.")
                        .textCase(nil)
                } footer: {
                    Text(viewModel.selectedCountText)
                }

                if let errorMessage = viewModel.errorMessage {
                    InlineError(message: errorMessage)
                }
            }
            .navigationTitle("Which services do you have?")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task {
                        if await viewModel.save() {
                            onSaved()
                            dismiss()
                        }
                    }
                } label: {
                    Text(viewModel.selected.isEmpty ? "I don't have any of these" : "Save")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.isSaving)
                .padding()
                .background(.bar)
            }
        }
        .task { await viewModel.load() }
    }
}

/// Én tjeneste: mærke, navn og flueben. Hele rækken kan trykkes.
private struct ServiceRow: View {
    let service: StreamingService
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text(service.badge)
                    .font(.footnote.bold())
                    .frame(width: 32, height: 32)
                    .background(.quaternary, in: .rect(cornerRadius: 8))
                Text(service.name)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(service.name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    StreamingServicesView(viewModel: StreamingServicesViewModel(
        preferencesService: MockPreferencesService(stored: StreamingPreferences(services: [.netflix, .tv2Play]))
    ))
}
