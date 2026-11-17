//
//  TasteView.swift
//  CineMatch
//

import SwiftUI

/// Gå film igennem én ad gangen: Like, Dislike eller "Haven't seen".
/// Man kan også swipe kortet til højre (like) eller venstre (dislike).
struct TasteView: View {
    let viewModel: TasteViewModel

    /// Hvor langt kortet er trukket. Over `swipeThreshold` tæller det som et svar.
    @State private var dragOffset: CGSize = .zero
    private let swipeThreshold: CGFloat = 110

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView("Loading movies …")
            case .failed(let message):
                ContentUnavailableView {
                    Label("Something went wrong", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await viewModel.load() } }
                    ShowLogButton()
                }
            case .loaded:
                content
            }
        }
        .navigationTitle("Swipe")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Undo", systemImage: "arrow.uturn.backward") {
                    Task { await viewModel.undo() }
                }
                .disabled(!viewModel.canUndo)
            }
        }
        .task {
            if viewModel.state == .loading { await viewModel.load() }
        }
    }

    private var content: some View {
        VStack(spacing: 16) {
            progressHeader

            if let title = viewModel.current {
                MovieCardView(title: title, posterURL: viewModel.posterURLs[title.id])
                    .overlay(alignment: .top) { swipeLabel }
                    .offset(x: dragOffset.width)
                    .rotationEffect(.degrees(Double(dragOffset.width) / 25))
                    .gesture(swipeGesture)
                    .id(title.id)
                    .transition(.asymmetric(insertion: .scale(scale: 0.95).combined(with: .opacity), removal: .opacity))
            } else {
                ContentUnavailableView(
                    "That's all for now",
                    systemImage: "checkmark.circle",
                    description: Text("Open Swipe picks to see your recommendations.")
                )
                .frame(maxHeight: .infinity)
            }

            if let errorMessage = viewModel.errorMessage {
                InlineError(message: errorMessage)
            }

            answerButtons
        }
        .padding()
        .animation(.spring(duration: 0.3), value: viewModel.current?.id)
        // Hent plakater, hver gang et nyt kort kommer frem.
        .task(id: viewModel.current?.id) { await viewModel.loadPosters() }
    }

    // MARK: - Dele

    private var progressHeader: some View {
        VStack(spacing: 6) {
            ProgressView(
                value: Double(min(viewModel.progressCount, TasteInput.minimumCount)),
                total: Double(TasteInput.minimumCount)
            )
            Text(progressText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var progressText: String {
        let missing = TasteInput.minimumCount - viewModel.progressCount
        switch (viewModel.input, viewModel.hasEnoughForRecommendations) {
        case (.likes, true):
            return "\(viewModel.likeCount) likes · Open Swipe picks to get recommendations"
        case (.starRatings, true):
            return "\(viewModel.ratedCount) rated · Open Star picks to get recommendations"
        case (.likes, false):
            return "Like \(missing) more movies to get recommendations"
        case (.starRatings, false):
            return "Rate \(missing) more movies with stars to get recommendations"
        }
    }

    private var answerButtons: some View {
        HStack(spacing: 12) {
            Button {
                Task { await viewModel.dislike() }
            } label: {
                Label("Dislike", systemImage: "hand.thumbsdown.fill")
                    .frame(maxWidth: .infinity)
            }
            .tint(.red)

            Button {
                viewModel.skip()
            } label: {
                Label("Haven't seen", systemImage: "eye.slash")
                    .frame(maxWidth: .infinity)
            }
            .tint(.gray)

            Button {
                Task { await viewModel.like() }
            } label: {
                Label("Like", systemImage: "hand.thumbsup.fill")
                    .frame(maxWidth: .infinity)
            }
            .tint(.green)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .labelStyle(.iconOnly)
        .font(.title2)
        .disabled(viewModel.current == nil)
    }

    /// "LIKE"/"NOPE"-skilt, mens kortet trækkes.
    @ViewBuilder
    private var swipeLabel: some View {
        if dragOffset.width > 30 {
            stamp("LIKE", color: .green)
        } else if dragOffset.width < -30 {
            stamp("NOPE", color: .red)
        }
    }

    private func stamp(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.title.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 3))
            .opacity(min(abs(Double(dragOffset.width)) / Double(swipeThreshold), 1))
            .padding(.top, 24)
    }

    private var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { dragOffset = $0.translation }
            .onEnded { value in
                let width = value.translation.width
                withAnimation(.spring(duration: 0.3)) { dragOffset = .zero }
                if width > swipeThreshold {
                    Task { await viewModel.like() }
                } else if width < -swipeThreshold {
                    Task { await viewModel.dislike() }
                }
            }
    }
}

#Preview {
    NavigationStack {
        TasteView(viewModel: TasteViewModel(
            movieDataService: MockMovieDataService(),
            tasteSignalService: MockTasteSignalService()
        ))
    }
}
