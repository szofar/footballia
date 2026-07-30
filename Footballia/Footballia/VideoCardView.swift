import SwiftUI

struct VideoCardView: View {
    let match: Match
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnailArea
            infoArea
        }
        .background(Color(red: 0.12, green: 0.12, blue: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(isHovered ? 0.14 : 0.05), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.025 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.5 : 0.2),
                radius: isHovered ? 18 : 8,
                y: isHovered ? 10 : 4)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isHovered)
        .onHover { isHovered = $0 }
    }

    private var thumbnailArea: some View {
        ZStack {
            Color(red: 0.1, green: 0.1, blue: 0.13)

            if let url = match.thumbnailURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholder
                    case .empty:
                        ProgressView().tint(.green).controlSize(.small)
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }

            // Hover play overlay
            if isHovered {
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
            AsyncImage(url: url) { phase in
                if case .success(let img) = phase {
                    img.resizable().aspectRatio(contentMode: .fit)
                } else {
                    Color.clear
                }
            }
            .frame(width: 16, height: 16)
        }
    }

    private var placeholder: some View {
        Image(systemName: "sportscourt")
            .font(.system(size: 26))
            .foregroundColor(.white.opacity(0.12))
    }
}
