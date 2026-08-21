import SwiftUI

struct VideoCardView: View {
    let match: Match
    #if os(tvOS)
    @Environment(\.isFocused) private var isFocused
    private var isHighlighted: Bool { isFocused }
    #else
    @State private var isHovered = false
    private var isHighlighted: Bool { isHovered }
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnailArea
            infoArea
        }
        .background(Color(red: 0.12, green: 0.12, blue: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(isHighlighted ? 0.14 : 0.05), lineWidth: 1)
        )
        .scaleEffect(isHighlighted ? 1.025 : 1.0)
        .shadow(color: .black.opacity(isHighlighted ? 0.5 : 0.2),
                radius: isHighlighted ? 18 : 8,
                y: isHighlighted ? 10 : 4)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isHighlighted)
        #if !os(tvOS)
        .onHover { isHovered = $0 }
        #endif
    }

    private var thumbnailArea: some View {
        ZStack {
            HStack(spacing: 1) {
                teamHalf(name: match.homeTeam, logoURL: match.homeTeamLogoURL)
                teamHalf(name: match.awayTeam, logoURL: match.awayTeamLogoURL)
            }

            if isHighlighted {
                Color.black.opacity(0.38)
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 52, height: 52)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .offset(x: 2)
                    )
            }
        }
        .aspectRatio(16 / 9, contentMode: .fill)
        .clipped()
    }

    private func teamHalf(name: String, logoURL: URL?) -> some View {
        ZStack {
            Color(red: 0.1, green: 0.1, blue: 0.13)
            Group {
                if let url = logoURL {
                    CachedAsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().aspectRatio(contentMode: .fit)
                        } else {
                            teamInitials(name: name)
                        }
                    }
                } else {
                    teamInitials(name: name)
                }
            }
            .frame(width: 52, height: 52)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func teamInitials(name: String) -> some View {
        Text(String(name.prefix(2)).uppercased())
            .font(.system(size: 20, weight: .bold))
            .foregroundColor(.white.opacity(0.25))
    }

    private var infoArea: some View {
        VStack(alignment: .leading, spacing: 5) {
            teamsRow

            if !match.competition.isEmpty {
                Text(match.competition)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.green.opacity(0.85))
                    .lineLimit(1)
            }

            HStack(spacing: 5) {
                if !match.stage.isEmpty {
                    Text(match.stage)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.35))
                        .lineLimit(1)
                    if !match.date.isEmpty {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 2, height: 2)
                    }
                }
                if !match.date.isEmpty {
                    Text(match.date)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.35))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var teamsRow: some View {
        HStack(spacing: 3) {
            HStack(spacing: 4) {
                teamFlag(url: match.homeTeamLogoURL)
                Text(match.homeTeam)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("vs")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.3))
                .padding(.horizontal, 2)

            HStack(spacing: 4) {
                teamFlag(url: match.awayTeamLogoURL)
                Text(match.awayTeam)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func teamFlag(url: URL?) -> some View {
        if let url {
            CachedAsyncImage(url: url) { phase in
                if case .success(let img) = phase {
                    img.resizable().aspectRatio(contentMode: .fit)
                } else {
                    Color.clear
                }
            }
            .frame(width: 16, height: 16)
        }
    }

}
