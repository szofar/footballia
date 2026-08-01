import SwiftUI

struct TeamSelectorView: View {
    let teams: [Team]
    let selectedSlug: String?
    let onSelect: (String?) -> Void

    private let rows = [GridItem(.fixed(72))]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: rows, spacing: 8) {
                allButton
                ForEach(teams) { team in
                    TeamChip(team: team, isSelected: selectedSlug == team.slug) {
                        onSelect(selectedSlug == team.slug ? nil : team.slug)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 10)
        }
        .frame(height: 92)
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    private var allButton: some View {
        let active = selectedSlug == nil
        return Button {
            onSelect(nil)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "rectangle.grid.2x2.fill")
                    .font(.system(size: 20))
                    .foregroundColor(active ? .green : .white.opacity(0.45))
                    .frame(height: 30)
                Text("All")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(active ? .green : .white.opacity(0.45))
            }
            .frame(width: 68, height: 64)
            .background(active ? Color.green.opacity(0.12) : Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(active ? Color.green.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct TeamChip: View {
    let team: Team
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 5) {
                AsyncImage(url: team.logoURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fit)
                    case .failure:
                        Circle()
                            .fill(Color.white.opacity(0.15))
                            .overlay(
                                Text(String(team.name.prefix(2)).uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white.opacity(0.5))
                            )
                    default:
                        Circle().fill(Color.white.opacity(0.06))
                    }
                }
                .frame(width: 30, height: 30)

                Text(team.name)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(isSelected ? .green : .white.opacity(0.65))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 68, height: 64)
            .background(isSelected ? Color.green.opacity(0.12) : Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.green.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
