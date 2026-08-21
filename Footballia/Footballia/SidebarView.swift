import SwiftUI

struct SidebarView: View {
    let sections: [SidebarSection]
    @Binding var selected: SidebarSection

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
                ForEach(sections) { section in
                    SidebarIconButton(
                        section: section,
                        isSelected: selected == section,
                        action: { selected = section }
                    )
                }
            }
            .padding(.vertical, 12)

            Spacer()
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

#if os(iOS)
/// Horizontal navigation bar used on mobile in place of the left sidebar. The app logo is only
/// rendered when `showLogo` is true (landscape); portrait hides it to reclaim the width.
struct TopMenuBar: View {
    let sections: [SidebarSection]
    @Binding var selected: SidebarSection
    let showLogo: Bool

    var body: some View {
        HStack(spacing: 8) {
            if showLogo {
                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .padding(.leading, 12)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(sections) { section in
                        TopMenuButton(
                            section: section,
                            isSelected: selected == section,
                            action: { selected = section }
                        )
                    }
                }
                .padding(.horizontal, showLogo ? 4 : 12)
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TopMenuButton: View {
    let section: SidebarSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                Text(section.rawValue)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
            }
            .foregroundColor(isSelected ? .green : .white.opacity(0.5))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.green.opacity(0.14) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.13), value: isSelected)
    }
}
#endif
