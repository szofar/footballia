import SwiftUI

struct SidebarView: View {
    @Binding var selected: SidebarSection
    let onLogout: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // App mark
            Image(systemName: "sportscourt.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.green)
                .frame(height: 60)

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)

            // Nav icons
            VStack(spacing: 2) {
                ForEach(SidebarSection.allCases) { section in
                    SidebarIconButton(
                        section: section,
                        isSelected: selected == section,
                        action: { selected = section }
                    )
                }
            }
            .padding(.vertical, 12)

            Spacer()

            // Sign out
            Button(action: onLogout) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.28))
                    .frame(width: 72, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Sign Out")
            .padding(.bottom, 10)
        }
    }
}

private struct SidebarIconButton: View {
    let section: SidebarSection
    let isSelected: Bool
    let action: () -> Void
    #if os(tvOS)
    @Environment(\.isFocused) private var isFocused
    private var isHighlighted: Bool { isFocused }
    #else
    @State private var isHovered = false
    private var isHighlighted: Bool { isHovered }
    #endif

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(background)
                    .frame(width: 46, height: 46)

                Image(systemName: section.systemImage)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(iconColor)
            }
            .frame(width: 72, height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(section.rawValue)
        #if !os(tvOS)
        .onHover { isHovered = $0 }
        #endif
        .animation(.easeInOut(duration: 0.13), value: isHighlighted)
        .animation(.easeInOut(duration: 0.13), value: isSelected)
    }

    private var background: Color {
        if isSelected { return .green.opacity(0.14) }
        if isHighlighted { return .white.opacity(0.06) }
        return .clear
    }

    private var iconColor: Color {
        if isSelected { return .green }
        if isHighlighted { return .white.opacity(0.65) }
        return .white.opacity(0.38)
    }
}
