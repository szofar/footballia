import SwiftUI

struct SearchView: View {
    @Environment(FootballiaService.self) private var service
    @State private var query = ""
    @State private var mode: SearchMode = .players
    @State private var selectedSuggestion: SearchSuggestion? = nil
    @State private var selectedMatch: Match? = nil
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                searchBar

                if let suggestion = selectedSuggestion {
                    matchPhase(for: suggestion)
                } else {
                    suggestionPhase
                }
            }
            .allowsHitTesting(selectedMatch == nil)

            if let match = selectedMatch {
                VideoPlayerOverlay(match: match) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        selectedMatch = nil
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .center)))
                .zIndex(10)
            }
        }
        // Live search: task is cancelled and restarted whenever query or mode changes
        .task(id: "\(query)-\(mode.rawValue)") {
            selectedSuggestion = nil
            let q = query.trimmingCharacters(in: .whitespaces)
            guard !q.isEmpty else { service.clearSearch(); return }
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
            await service.search(query: q, mode: mode)
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Mode toggle
                HStack(spacing: 0) {
                    ForEach(SearchMode.allCases) { m in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                mode = m
                                selectedSuggestion = nil
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: m == .players ? "person.2.fill" : "flag.fill")
                                    .font(.system(size: 11))
                                Text(m.rawValue)
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(mode == m ? .black : .white.opacity(0.5))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(mode == m ? Color.green : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Text field
                HStack(spacing: 8) {
                    if service.isSearching {
                        ProgressView().tint(.green).controlSize(.small)
                    } else {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(fieldFocused ? 0.7 : 0.3))
                            .font(.system(size: 14))
                    }

                    TextField(mode.placeholder, text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .focused($fieldFocused)

                    if !query.isEmpty {
                        Button {
                            query = ""
                            selectedSuggestion = nil
                            service.clearSearch()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white.opacity(0.3))
                                .font(.system(size: 13))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(fieldFocused ? 0.2 : 0.0), lineWidth: 1)
                )
                .animation(.easeInOut(duration: 0.15), value: fieldFocused)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
    }

    // MARK: - Suggestion phase (list of player/team names)

    @ViewBuilder
    private var suggestionPhase: some View {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            emptyPrompt(
                icon: "magnifyingglass",
                text: "Type a \(mode == .players ? "player" : "team") name to search."
            )
        } else if service.isSearching {
            loadingView(text: "Searching…")
        } else if let err = service.searchError, service.searchSuggestions.isEmpty {
            emptyPrompt(icon: "exclamationmark.magnifyingglass", text: err)
        } else if service.searchSuggestions.isEmpty {
            emptyPrompt(icon: "magnifyingglass", text: "No results.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Text("\(service.searchSuggestions.count) results")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.45))
                        Spacer()
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                    VStack(spacing: 2) {
                        ForEach(service.searchSuggestions) { suggestion in
                            SuggestionRow(suggestion: suggestion) {
                                fieldFocused = false
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    selectedSuggestion = suggestion
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Match phase (grid for selected player/team)

    @ViewBuilder
    private func matchPhase(for suggestion: SearchSuggestion) -> some View {
        VStack(spacing: 0) {
            // Back bar
            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { selectedSuggestion = nil }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Results")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.55))
                }
                .buttonStyle(.plain)

                Text(suggestion.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer()

                if service.isLoadingSearchMatches {
                    ProgressView().tint(.green).controlSize(.small)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(Color(red: 0.07, green: 0.07, blue: 0.09))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            }

            if service.isLoadingSearchMatches && service.searchResults.isEmpty {
                loadingView(text: "Loading matches…")
            } else if service.searchResults.isEmpty {
                emptyPrompt(icon: "film.stack", text: "No matches found for \(suggestion.name).")
            } else {
                VideoGridView(
                    title: suggestion.name,
                    matches: service.searchResults,
                    isLoading: service.isLoadingSearchMatches,
                    currentPage: service.searchCurrentPage,
                    hasNextPage: service.searchHasNextPage,
                    isReversed: service.searchPaginationReversed,
                    onSelect: { selectedMatch = $0 },
                    onNextPage: {
                        Task { await service.loadSearchPage(service.searchCurrentPage + 1, for: suggestion) }
                    },
                    onPreviousPage: {
                        Task { await service.loadSearchPage(service.searchCurrentPage - 1, for: suggestion) }
                    }
                )
            }
        }
        .task { await service.loadMatchesForSuggestion(suggestion) }
    }

    // MARK: - Helpers

    private func loadingView(text: String) -> some View {
        VStack(spacing: 14) {
            ProgressView().tint(.green).controlSize(.large)
            Text(text).font(.subheadline).foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyPrompt(icon: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 38))
                .foregroundColor(.white.opacity(0.1))
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.35))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Suggestion row

private struct SuggestionRow: View {
    let suggestion: SearchSuggestion
    let onTap: () -> Void
    #if os(tvOS)
    @Environment(\.isFocused) private var isFocused
    private var isHighlighted: Bool { isFocused }
    #else
    @State private var isHovered = false
    private var isHighlighted: Bool { isHovered }
    #endif

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: suggestion.mode == .players ? "person.fill" : "shield.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.green.opacity(0.7))
                    .frame(width: 22)

                Text(suggestion.name)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.2))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(isHighlighted ? 0.07 : 0.0))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        #if !os(tvOS)
        .onHover { isHovered = $0 }
        #endif
        .animation(.easeInOut(duration: 0.1), value: isHighlighted)
    }
}
