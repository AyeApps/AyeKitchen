import SwiftUI

/// Hoja para crear una cuenta Aye desde la app.
struct SignUpView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email: String
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    init(initialEmail: String? = nil) {
        _email = State(initialValue: initialEmail ?? "")
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespaces)
    }

    private var isEmailValid: Bool {
        guard let atIndex = trimmedEmail.firstIndex(of: "@") else { return false }
        let afterAt = trimmedEmail[trimmedEmail.index(after: atIndex)...]
        return afterAt.contains(".")
    }

    private var canSubmit: Bool {
        (1...100).contains(trimmedName.count)
            && isEmailValid
            && password.count >= 8
            && !isWorking
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    Text("Es la misma cuenta Aye de las demás apps.")
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)

                    formFields

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
                            Text("Crear cuenta")
                        }
                    }
                    .buttonStyle(.kitchenPrimary)
                    .disabled(!canSubmit)
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(.canvasBackground)
            .navigationTitle("Crear cuenta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
            }
            .onSubmit {
                if canSubmit { Task { await submit() } }
            }
        }
    }

    private var formFields: some View {
        VStack(spacing: Spacing.lg) {
            KitchenTextField(
                label: "Nombre",
                text: $name,
                contentType: .name,
                capitalization: .words
            )

            KitchenTextField(
                label: "Correo",
                text: $email,
                keyboard: .emailAddress,
                contentType: .username,
                capitalization: .never,
                autocorrection: false
            )

            VStack(alignment: .leading, spacing: Spacing.xs) {
                KitchenTextField(
                    label: "Contraseña",
                    text: $password,
                    isSecure: true,
                    contentType: .newPassword,
                    capitalization: .never,
                    autocorrection: false
                )

                Text("Mínimo 8 caracteres")
                    .font(.footnote)
                    .foregroundStyle(.inkMuted)
            }
        }
    }

    private func submit() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await session.signUp(
                name: trimmedName,
                email: trimmedEmail,
                password: password
            )
        } catch let error as APIError {
            errorMessage = switch error.status {
            case 400 where error.localizedDescription.contains("Turnstile"):
                "Por ahora, desde el iPhone crea tu cuenta con Apple."
            case 400:
                error.localizedDescription
            case 422:
                "Revisa tu nombre, correo y contraseña."
            default:
                error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    SignUpView()
        .environment(SessionStore())
        .fontDesign(.rounded)
}

#Preview("Letra grande") {
    SignUpView()
        .environment(SessionStore())
        .fontDesign(.rounded)
        .dynamicTypeSize(.accessibility3)
}
