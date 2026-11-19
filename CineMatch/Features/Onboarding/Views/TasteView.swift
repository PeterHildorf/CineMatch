//
//  TasteView.swift
//  CineMatch
//

import SwiftUI

/// Gå film igennem én ad gangen og giv hver en dom: Horrible, Bad, Great, Fantastic eller Haven't seen.
/// Genveje: swipe højre = Great, venstre = Bad, op = Fantastic, ned = Horrible.
/// "Haven't seen" er kun en knap, så man ikke kommer til at springe en film over ved et uheld.
///
/// I onboarding (`isOnboarding`) vises en kort guide til swipes i 5 sekunder, og fremskridtet
/// tæller mod 10 film. Bagefter kan guiden altid vises igen med "?".
struct TasteView: View {
    let viewModel: TasteViewModel
    var isOnboarding = false
    /// Tekst under "That's all for now", fx hvor anbefalingerne findes.
    var finishedHint = "Open Recommendations to see your picks."

    @State private var isShowingGuide = false

    /// Hvor langt kortet er trukket. Over `swipeThreshold` tæller det som et svar.
    @State private var dragOffset: CGSize = .zero
    private let swipeThreshold: CGFloat = 110
    /// Vibration: tæller op ved hvert svar/undo, så `sensoryFeedback` kan reagere på det.
    @State private var hapticTick = 0
    /// Det svar, vibrationen skal passe til. `nil` = undo.
    @State private var hapticVerdict: Verdict?

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
                    playHaptic(for: nil)
                    Task { await viewModel.undo() }
                }
                .disabled(!viewModel.canUndo)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("How to swipe", systemImage: "questionmark.circle") { showGuide() }
            }
        }
        .overlay {
            if isShowingGuide {
                SwipeGuide()
                    .transition(.opacity)
                    .onTapGesture { withAnimation { isShowingGuide = false } }
            }
        }
        .task {
            if viewModel.state == .loading { await viewModel.load() }
            if isOnboarding { showGuide() }
        }
    }

    /// Viser guiden og lader den fade ud efter 5 sekunder (eller ved tryk).
    private func showGuide() {
        withAnimation { isShowingGuide = true }
        Task {
            try? await Task.sleep(for: .seconds(5))
            withAnimation(.easeOut(duration: 0.6)) { isShowingGuide = false }
        }
    }

    private var content: some View {
        VStack(spacing: 16) {
            progressHeader

            if let title = viewModel.current {
                MovieCardView(title: title, posterURL: viewModel.posterURLs[title.id])
                    // Plakatens eget format (2:3), så hele plakaten vises i stedet for et udsnit.
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .top) { swipeLabel }
                    .offset(dragOffset)
                    .rotationEffect(.degrees(Double(dragOffset.width) / 25))
                    .gesture(swipeGesture)
                    .id(title.id)
                    .transition(.asymmetric(insertion: .scale(scale: 0.95).combined(with: .opacity), removal: .opacity))
            } else {
                ContentUnavailableView(
                    "That's all for now",
                    systemImage: "checkmark.circle",
                    description: Text(finishedHint)
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
        // Et lille klik, når kortet trækkes langt nok til at tælle (og når retningen skifter).
        .sensoryFeedback(trigger: armedVerdict) { _, new in
            new == nil ? nil : .impact(weight: .light, intensity: 0.7)
        }
        // Et svar eller undo: vibrationen passer til dommen.
        .sensoryFeedback(trigger: hapticTick) { _, _ in Self.haptic(for: hapticVerdict) }
        // Svaret kunne ikke gemmes.
        .sensoryFeedback(trigger: viewModel.errorMessage) { _, new in new == nil ? nil : .error }
        // Hent selve billederne til de næste kort i baggrunden, så de er klar, når brugeren swiper.
        .onChange(of: viewModel.posterURLs, initial: true) { _, urls in
            for title in viewModel.queue.prefix(TasteViewModel.posterPrefetchCount) {
                PosterCache.shared.prefetch(urls[title.id])
            }
        }
    }

    // MARK: - Dele

    private var progressHeader: some View {
        VStack(spacing: 6) {
            ProgressView(value: progressValue)
            Text(progressText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// 0–1. Onboarding: først mod 10 film, derefter mod 5 Great/Fantastic, hvis de mangler.
    private var progressValue: Double {
        if isOnboarding, viewModel.answeredCount < TasteViewModel.onboardingSwipes {
            return Double(viewModel.answeredCount) / Double(TasteViewModel.onboardingSwipes)
        }
        return min(Double(viewModel.progressCount) / Double(TasteInput.minimumCount), 1)
    }

    private var progressText: String {
        if isOnboarding {
            let swipesLeft = TasteViewModel.onboardingSwipes - viewModel.answeredCount
            let likesLeft = TasteViewModel.minimumLikes - viewModel.likeCount
            if swipesLeft > 0 {
                return "Rate \(swipesLeft) more \(swipesLeft == 1 ? "movie" : "movies") to get your picks"
            }
            if likesLeft > 0 {
                return "Almost there – rate \(likesLeft) more Great or Fantastic"
            }
            return "Your picks are ready"
        }
        let missing = TasteInput.minimumCount - viewModel.progressCount
        switch (viewModel.input, viewModel.hasEnoughForRecommendations) {
        case (.likes, true), (.starRatings, true):
            return "\(viewModel.seenCount) rated · the more you rate, the better your picks"
        case (.likes, false):
            return "Rate \(missing) more \(missing == 1 ? "movie" : "movies") Great or Fantastic to get picks"
        case (.starRatings, false):
            return "Rate \(missing) more \(missing == 1 ? "movie" : "movies") you've seen to get picks"
        }
    }

    private var answerButtons: some View {
        VerdictButtons(isEnabled: viewModel.current != nil) { verdict in
            playHaptic(for: verdict)
            Task { await viewModel.rate(verdict) }
        }
    }

    /// Den dom, kortet lander på, hvis det slippes nu. `nil` = for kort et træk.
    private func verdict(for translation: CGSize, threshold: CGFloat) -> Verdict? {
        let horizontal = abs(translation.width) > abs(translation.height)
        if horizontal {
            if translation.width > threshold { return .great }
            if translation.width < -threshold { return .bad }
        } else {
            if translation.height < -threshold { return .fantastic }
            if translation.height > threshold { return .horrible }
        }
        return nil
    }

    /// "GREAT"/"BAD"/"FANTASTIC"/"HAVEN'T SEEN"-skilt, mens kortet trækkes.
    @ViewBuilder
    private var swipeLabel: some View {
        if let verdict = verdict(for: dragOffset, threshold: 30) {
            stamp(verdict.label.uppercased(), color: verdict.tint)
        }
    }

    private func stamp(_ text: String, color: Color) -> some View {
        let distance = max(abs(dragOffset.width), abs(dragOffset.height))
        return Text(text)
            .font(.title.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 3))
            .opacity(min(Double(distance) / Double(swipeThreshold), 1))
            .padding(.top, 24)
    }

    // MARK: - Vibration

    /// Dommen, kortet lander på, hvis det slippes nu (over tærsklen). Skifter → klik.
    private var armedVerdict: Verdict? {
        verdict(for: dragOffset, threshold: swipeThreshold)
    }

    private func playHaptic(for verdict: Verdict?) {
        hapticVerdict = verdict
        hapticTick += 1
    }

    /// Fantastic føles som en lille fejring, Horrible som et tungt bump. Undo og "Haven't seen" er bløde.
    private static func haptic(for verdict: Verdict?) -> SensoryFeedback {
        switch verdict {
        case .fantastic: .success
        case .great: .impact(weight: .medium)
        case .neutral: .impact(weight: .light)
        case .bad: .impact(weight: .medium, intensity: 0.8)
        case .horrible: .impact(weight: .heavy)
        case .notSeen, nil: .impact(flexibility: .soft, intensity: 0.5)
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { dragOffset = $0.translation }
            .onEnded { value in
                let verdict = verdict(for: value.translation, threshold: swipeThreshold)
                withAnimation(.spring(duration: 0.3)) { dragOffset = .zero }
                if let verdict {
                    playHaptic(for: verdict)
                    Task { await viewModel.rate(verdict) }
                }
            }
    }
}

/// Kort guide til swipes. Vises over kortet i onboarding og ved "?".
private struct SwipeGuide: View {
    var body: some View {
        VStack(spacing: 18) {
            Text("How to rate")
                .font(.title2.bold())
            row("arrow.up", .fantastic, "Swipe up")
            row("arrow.right", .great, "Swipe right")
            row("arrow.left", .bad, "Swipe left")
            row("arrow.down", .horrible, "Swipe down")
            Text("In between? Tap \"Neutral\". Don't know the movie? Tap \"Haven't seen\" to skip it for now.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.25))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Tap to close")
    }

    private func row(_ arrow: String, _ verdict: Verdict, _ gesture: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: arrow)
                .font(.title2.bold())
                .frame(width: 32)
            Text(gesture)
                .frame(maxWidth: .infinity, alignment: .leading)
            Label(verdict.label, systemImage: verdict.systemImage)
                .foregroundStyle(verdict.tint)
                .fontWeight(.semibold)
        }
    }
}

#Preview {
    NavigationStack {
        TasteView(viewModel: TasteViewModel(
            movieDataService: MockMovieDataService(titles: DemoData.swipeTitles),
            tasteSignalService: MockTasteSignalService(),
            mediaService: MockTitleMediaService.demo
        ), isOnboarding: true)
    }
}
