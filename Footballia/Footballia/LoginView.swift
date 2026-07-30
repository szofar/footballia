import SwiftUI

struct LoginView: View {
    @Environment(FootballiaService.self) private var service
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    enum Field { case email, password }

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.05).ignoresSafeArea()

            VStack(spacing: 52) {
                logoSection
                formSection
            }
            .padding(40)
        }
        .frame(minWidth: 480, minHeight: 540)
    }

    private var logoSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "sportscourt.fill")
                    .font(.system(size: 46))
                    .foregroundColor(.green)
            }
            Text("FOOTBALLIA")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .tracking(6)
            Text("The Football Video Archive")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.35))
        }
    }

    private var formSection: some View {
        VStack(spacing: 14) {
            styledField("Email", text: $email, isSecure: false, field: .email)
            styledField("Password", text: $password, isSecure: true, field: .password)

            if let error = service.loginError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text(error)
                }
                .font(.caption)
                .foregroundColor(.red.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .transition(.opacity)
            }

            Button {
                Task { await service.login(email: email, password: password) }
            } label: {
                ZStack {
                    if service.isLoading {
                        ProgressView().progressViewStyle(.circular).controlSize(.small).tint(.black)
                    } else {
                        Text("Sign In")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.black)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.green.opacity(canSignIn ? 1 : 0.4))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canSignIn || service.isLoading)
            .animation(.easeInOut(duration: 0.2), value: canSignIn)
        }
        .frame(maxWidth: 360)
    }

    private var canSignIn: Bool { !email.isEmpty && !password.isEmpty }

    @ViewBuilder
    private func styledField(_ placeholder: String, text: Binding<String>, isSecure: Bool, field: Field) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(focusedField == field ? Color.green.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
                )
            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .textFieldStyle(.plain)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .focused($focusedField, equals: field)
        }
        .frame(height: 50)
        .animation(.easeInOut(duration: 0.15), value: focusedField == field)
    }
}
