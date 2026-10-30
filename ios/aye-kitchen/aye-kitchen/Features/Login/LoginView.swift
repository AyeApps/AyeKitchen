import AuthenticationServices
import SwiftUI

/// Entrar con la cuenta Aye (artboard "Entrar — iPhone").
struct LoginView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.colorScheme) private var colorScheme

    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showingSignUp = false

    @ScaledMetric(relativeTo: .largeTitle) private var logoSize: CGFloat = 88
    @ScaledMetric(relativeTo: .body) private var appleButtonHeight: CGFloat = 54

    private var canSubmit: Bool {
        email.contains("@") && !password.isEmpty && !isWorking
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                header
                form
                separator
                appleButton
                Text("Si ya usas otra app Aye, entra con esa misma cuenta.")
                    .font(.footnote)
                    .foregroundStyle(.inkMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.top, 48)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(.canvasBackground)
        .sheet(isPresented: $showingSignUp) {
            SignUpView(initialEmail: email)
        }
    }

    private var header: some View {
        VStack(spacing: 18) {
            Image(systemName: "birthday.cake")
                .font(.system(size: logoSize * 0.5, weight: .semibold))
                .foregroundStyle(.accentInk)
                .frame(width: logoSize, height: logoSize)
                .background(.accentFill, in: .rect(cornerRadius: 28))
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("¡Hola de nuevo!")
                    .font(.title.weight(.heavy))
                    .accessibilityAddTraits(.isHeader)
                Text("Entra para ver tus pedidos y lo que cuesta cada pastel.")
                    .font(.body)
                    .foregroundStyle(.inkMuted)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var form: some View {
        VStack(spacing: Spacing.lg) {
            KitchenTextField(
                label: "Correo", text: $email,
                keyboard: .emailAddress, contentType: .username, capitalization: .never, autocorrection: false
            )
            KitchenTextField(
                label: "Contraseña", text: $password,
                isSecure: true, contentType: .password, capitalization: .never, autocorrection: false
            )

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.warningText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.md)
                    .background(.warningSoft, in: .rect(cornerRadius: Radius.control))
            }

            Button {
                Task { await submit() }
            } label: {
                if isWorking {
                    ProgressView().tint(.accentInk)
                } else {
                    Text("Entrar")
                }
            }
            .buttonStyle(.kitchenPrimary)
            .disabled(!canSubmit)

            Button {
                showingSignUp = true
            } label: {
                Text("¿No tienes cuenta? Crear una")
                    .font(.subheadline)
                    .foregroundStyle(.accentInk)
            }
            .disabled(isWorking)
        }
        .onSubmit {
            if canSubmit { Task { await submit() } }
        }
    }

    private var separator: some View {
        HStack(spacing: Spacing.md) {
            Rectangle().fill(.borderLine).frame(height: 1)
            Text("o entra con")
                .font(.footnote)
                .foregroundStyle(.inkMuted)
                .fixedSize()
            Rectangle().fill(.borderLine).frame(height: 1)
        }
        .accessibilityHidden(true)
    }

    private var appleButton: some View {
        SignInWithAppleButton(.continue) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                Task { await signInWithApple(authorization) }
            case .failure(let error):
                if (error as? ASAuthorizationError)?.code != .canceled {
                    errorMessage = "No pudimos entrar con Apple. Intenta de nuevo."
                }
            }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: appleButtonHeight)
        .clipShape(.rect(cornerRadius: Radius.card))
        .disabled(isWorking)
    }

    private func submit() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await session.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
        } catch let error as APIError {
            errorMessage = switch error.status {
            case 401: "Ese correo y esa contraseña no coinciden."
            // aye-auth pide verificación de Cloudflare al entrar con correo; en la app se entra con Apple.
            case 400: "Desde el iPhone entra con Apple."
            case 404: "No hay una cuenta con ese correo. Toca Crear una para hacerla."
            case 423: error.localizedDescription
            default: error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func signInWithApple(_ authorization: ASAuthorization) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await session.signInWithApple(authorization)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    LoginView()
        .environment(SessionStore())
        .fontDesign(.rounded)
}
