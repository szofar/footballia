import SwiftUI

/// Minimal account tab: who's signed in, Master entitlement, and sign out.
struct ProfileView: View {
    @Environment(FootballiaService.self) private var service
    @State private var confirmingLogout = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Profile")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                    Text("Account and access")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.35))
                }
                .padding(.top, 30)

                accountCard
                masterCard
                signOutButton

                Spacer(minLength: 20)
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
        return 100
        #else
        return 28
        #endif
    }

    // MARK: - Account

    private var accountCard: some View {
        card {
            HStack(spacing: 14) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 38))
                    .foregroundColor(.green.opacity(0.8))

                VStack(alignment: .leading, spacing: 3) {
                    Text(service.accountEmail ?? "Signed in")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text("footballia.eu")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.35))
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Master status

    private var masterCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: service.hasMasterAccess ? "crown.fill" : "lock.fill")
                        .font(.system(size: 16))
                        .foregroundColor(service.hasMasterAccess ? .green : .white.opacity(0.3))

                    Text(service.hasMasterAccess ? "Master access" : "No Master access")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer(minLength: 0)

                    if !service.didCheckMasterAccess {
                        ProgressView().tint(.green).controlSize(.small)
                    }
                }

                Text(service.hasMasterAccess
                     ? "Master features such as the Calendar are unlocked on this account."
                     : "The Calendar is a Master feature. Visit footballia.eu/master in a browser to subscribe, then reopen the app.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Sign out

    private var signOutButton: some View {
        Button {
            if confirmingLogout {
                service.logout()
            } else {
                withAnimation(.easeInOut(duration: 0.15)) { confirmingLogout = true }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                Text(confirmingLogout ? "Tap again to confirm" : "Sign Out")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(confirmingLogout ? .white : .red.opacity(0.85))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(confirmingLogout ? Color.red.opacity(0.75) : Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.red.opacity(confirmingLogout ? 0 : 0.28), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Card chrome

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.12, green: 0.12, blue: 0.14))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
            )
    }
}
