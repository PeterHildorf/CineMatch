//
//  TodayView.swift
//  CineMatch
//

import SwiftUI

/// "Today": appens forside efter onboarding.
///
/// Øverst "Tonight's pick" som en stor hero med plakaten sløret i baggrunden – én film om dagen.
/// Har brugeren allerede set den, giver han den en dom (streak +1), og den næste anbefaling bliver aftenens pick.
/// Under den: "Make your picks sharper" og vandrette plakat-rækker (top 10, "Show more" op til 20).
/// Tryk på en plakat åbner detaljer; langt tryk giver "Seen it" direkte.
/// Anbefalingerne beregnes selv, når brugeren har bedømt flere film i Swipe eller Search.
struct TodayView: View {
    let viewModel: RecommendationsViewModel
    /// Knapperne "Swipe more" og "Search" – skifter fane.
    var onSwipeMore: () -> Void = {}
    var onSearch: () -> Void = {}

    /// Filmen, hvis detaljer vises i et ark.
    @State private var selected: RecommendationsViewModel.Item?

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView("Finding tonight's pick …")
            case .empty:
                ContentUnavailableView {
                    Label("No picks yet", systemImage: "sparkles")
                } description: {
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                    } else {
                        Text(viewModel.emptyHint)
                    }
                } actions: {
                    Button("Rate more in Swipe", action: onSwipeMore)
                        .buttonStyle(.borderedProminent)
                    Button("Try again") { Task { await viewModel.refresh() } }
                    if viewModel.errorMessage != nil { ShowLogButton() }
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("Something went wrong", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await viewModel.refresh() } }
                    ShowLogButton()
                }
            case .loaded(let items):
                content(items)
            }
        }
        .navigationTitle("Recommendations")
        // Ingen navigationsbar: fanen viser allerede navnet, og hero'en skal gå helt op i toppen.
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottom) {
            if viewModel.isRecomputing, case .loaded = viewModel.state {
                ProgressView("Updating your picks …")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: .capsule)
                    .padding(.bottom, 12)
            }
        }
        .sheet(item: $selected) { item in
            TitleDetailSheet(item: item, myServices: viewModel.myServices, onSeen: seenAction(for: item))
                .presentationDetents([.medium, .large])
        }
        .task { await viewModel.refresh() }
    }

    // MARK: - Indhold

    private func content(_ items: [RecommendationsViewModel.Item]) -> some View {
        let pick = items.first { $0.id == viewModel.dailyPickID }
        let list = items.filter { $0.id != viewModel.dailyPickID }
        let top = Array(list.prefix(RecommendationsViewModel.shownCount))
        let more = Array(list.dropFirst(RecommendationsViewModel.shownCount))

        return ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let pick {
                    DailyPickHero(
                        item: pick,
                        myServices: viewModel.myServices,
                        streak: viewModel.streak,
                        onSeen: seenAction(for: pick),
                        onAnother: { Task { await viewModel.anotherDailyPick() } },
                        onDetails: { selected = pick }
                    )
                }

                if let errorMessage = viewModel.errorMessage {
                    InlineError(message: errorMessage)
                        .padding(.horizontal)
                }

                SharpenCard(onSwipeMore: onSwipeMore, onSearch: onSearch)
                    .padding(.horizontal)

                if viewModel.canFilterByServices {
                    Toggle("Only my services", isOn: Binding(
                        get: { viewModel.preferences.onlyMyServices },
                        set: { isOn in Task { await viewModel.setOnlyMyServices(isOn) } }
                    ))
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal)
                }

                if viewModel.isFiltering {
                    ProgressView("Checking your services …")
                        .frame(maxWidth: .infinity)
                }

                if !top.isEmpty {
                    PosterShelf(
                        title: "Your top \(top.count)",
                        items: top,
                        firstRank: 1,
                        myServices: viewModel.myServices,
                        showMore: viewModel.canShowMore ? { Task { await viewModel.showMore() } } : nil,
                        onSelect: { selected = $0 },
                        onSeen: { item, verdict in Task { await viewModel.markSeen(item, verdict: verdict) } }
                    )
                }
                if !more.isEmpty {
                    PosterShelf(
                        title: "More for you",
                        items: more,
                        firstRank: top.count + 1,
                        myServices: viewModel.myServices,
                        showMore: nil,
                        onSelect: { selected = $0 },
                        onSeen: { item, verdict in Task { await viewModel.markSeen(item, verdict: verdict) } }
                    )
                }

                if let filterNote = viewModel.filterNote {
                    Text(filterNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }

                // TMDB og JustWatch kræver, at vi krediterer dem.
                Text("This product uses the TMDB API but is not endorsed or certified by TMDB. Streaming data by JustWatch.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
        .refreshable { await viewModel.refresh() }
        .animation(.default, value: items.map(\.id))
    }

    private func seenAction(for item: RecommendationsViewModel.Item) -> ((Verdict) -> Void)? {
        guard viewModel.canMarkSeen else { return nil }
        return { verdict in
            selected = nil
            Task { await viewModel.markSeen(item, verdict: verdict) }
        }
    }
}

// MARK: - Hero

/// "Tonight's pick": plakaten i midten, samme plakat sløret bag hele toppen.
private struct DailyPickHero: View {
    let item: RecommendationsViewModel.Item
    let myServices: Set<StreamingService>
    let streak: Int
    var onSeen: ((Verdict) -> Void)?
    let onAnother: () -> Void
    let onDetails: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("TONIGHT'S PICK")
                    .font(.caption.weight(.heavy))
                    .tracking(1.5)
                Spacer()
                if streak > 0 {
                    Label("\(streak)", systemImage: "flame.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.orange)
                        .accessibilityLabel("\(streak)-day streak")
                }
            }

            Button(action: onDetails) {
                PosterImage(url: item.media?.posterURL)
                    .frame(width: 210, height: 315)
                    .clipShape(.rect(cornerRadius: 18))
                    .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Details for \(item.displayTitle)")

            VStack(spacing: 4) {
                Text(item.displayTitle)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                if let title = item.title {
                    Text(RecommendationRow.subtitle(for: title))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let reason = item.recommendation.reason {
                Text(reason)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            if let media = item.media {
                WhereToWatch(media: media, myServices: myServices)
            }

            HStack(spacing: 12) {
                if let onSeen {
                    VerdictMenu(title: "Seen it? Rate it", size: .large, isProminent: true, onRate: onSeen)
                }
                Button(action: onAnother) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityLabel("Another pick")
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background { blurredPoster }
    }

    /// Plakaten sløret bag hero'en. Den fader ind fra toppen og ud mod bunden, så der ingen kanter er.
    /// Forstørret, så slørets bløde kanter i siderne ligger uden for skærmen.
    private var blurredPoster: some View {
        PosterImage(url: item.media?.posterURL)
            .scaleEffect(1.4)
            .blur(radius: 60)
            .opacity(0.55)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.2),
                        .init(color: .black, location: 0.6),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }
}

// MARK: - Plakat-rækker

/// Vandret række af plakater med overskrift. "Show more" ligger som sidste kort i rækken.
private struct PosterShelf: View {
    let title: String
    let items: [RecommendationsViewModel.Item]
    let firstRank: Int
    let myServices: Set<StreamingService>
    let showMore: (() -> Void)?
    let onSelect: (RecommendationsViewModel.Item) -> Void
    let onSeen: (RecommendationsViewModel.Item, Verdict) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.bold())
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        PosterTile(item: item, rank: firstRank + index, myServices: myServices)
                            .onTapGesture { onSelect(item) }
                            .contextMenu {
                                Section("Seen it?") {
                                    ForEach(Verdict.seenOptions.reversed()) { verdict in
                                        Button(verdict.label, systemImage: verdict.systemImage) { onSeen(item, verdict) }
                                    }
                                }
                            }
                    }
                    if let showMore {
                        Button(action: showMore) {
                            VStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.largeTitle)
                                Text("Show more")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(width: PosterTile.width, height: PosterTile.width * 1.5)
                            .background(.quaternary, in: .rect(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

/// Én plakat i en række: placering, titel og hvor den kan ses.
private struct PosterTile: View {
    static let width: CGFloat = 130

    let item: RecommendationsViewModel.Item
    let rank: Int
    let myServices: Set<StreamingService>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterImage(url: item.media?.posterURL)
                .frame(width: Self.width, height: Self.width * 1.5)
                .clipShape(.rect(cornerRadius: 14))
                .overlay(alignment: .topLeading) {
                    Text("\(rank)")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.white)
                        .frame(minWidth: 24, minHeight: 24)
                        .background(.black.opacity(0.6), in: .circle)
                        .padding(6)
                }

            Text(item.displayTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2, reservesSpace: true)

            if let provider = providerText {
                Text(provider)
                    .font(.caption)
                    .foregroundStyle(isOnMyServices ? Color.green : Color.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: Self.width)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows details. Touch and hold to rate it.")
    }

    private var isOnMyServices: Bool { item.media?.provider(in: myServices) != nil }

    private var providerText: String? {
        if let mine = item.media?.provider(in: myServices) { return "✓ \(mine.name)" }
        return item.media?.bestProvider?.name
    }
}

// MARK: - Detaljer

/// Arket, der åbner ved tryk på en plakat: alt om filmen og "Seen it".
private struct TitleDetailSheet: View {
    let item: RecommendationsViewModel.Item
    let myServices: Set<StreamingService>
    var onSeen: ((Verdict) -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 16) {
                    PosterImage(url: item.media?.posterURL)
                        .frame(width: 110, height: 165)
                        .clipShape(.rect(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.displayTitle)
                            .font(.title2.bold())
                        if let title = item.title {
                            Text(RecommendationRow.subtitle(for: title))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let director = title.director {
                                Text("Directed by \(director)")
                                    .font(.subheadline)
                            }
                        }
                        if let onSeen {
                            VerdictMenu(title: "Seen it? Rate it", size: .regular, onRate: onSeen)
                                .padding(.top, 6)
                        }
                    }
                }
                if let reason = item.recommendation.reason {
                    Label(reason, systemImage: "sparkles")
                        .font(.callout)
                }
                if let media = item.media {
                    WhereToWatch(media: media, myServices: myServices)
                }
                if let overview = item.title?.overview {
                    Text(overview)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
    }
}

// MARK: - Kort

/// "Make your picks sharper": viser brugeren, at flere bedømmelser giver bedre anbefalinger.
private struct SharpenCard: View {
    let onSwipeMore: () -> Void
    let onSearch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Make your picks sharper", systemImage: "scope")
                .font(.headline)
            Text("Every movie you rate changes your list right away.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button(action: onSwipeMore) {
                    Label("Swipe more", systemImage: "rectangle.stack")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button(action: onSearch) {
                    Label("Search", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .buttonBorderShape(.capsule)
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 18))
    }
}

#Preview {
    NavigationStack {
        TodayView(viewModel: RecommendationsViewModel(
            recommendationService: MockRecommendationService(stored: DemoData.recommendations),
            movieDataService: MockMovieDataService(titles: DemoData.titles),
            mediaService: MockTitleMediaService.demo,
            signalService: MockTasteSignalService(),
            dailyPicks: DailyPickStore(defaults: UserDefaults(suiteName: "preview.today")!, key: "preview"),
            title: "Recommendations"
        ))
    }
}
