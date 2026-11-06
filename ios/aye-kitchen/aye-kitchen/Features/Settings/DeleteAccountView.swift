import SwiftUI

/// Pantalla para eliminar la cuenta Aye y todos los datos asociados (Bloque I29).
struct DeleteAccountView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var model: DataDeletionModel
    @State private var showingDeleteConfirmation = false
    #if DEBUG
    var previewEmail: String?
    #endif

    @ScaledMetric(relativeTo: .headline) private var minButtonHeight: CGFloat = 56

    init(model: DataDeletionModel = DataDeletionModel()) {
        self._model = State(initialValue: model)
    }

    #if DEBUG
    init(model: DataDeletionModel = DataDeletionModel(), previewEmail: String? = nil) {
        self._model = State(initialValue: model)
        self.previewEmail = previewEmail
    }
    #endif

    private var accountEmail: String? {
        #if DEBUG
        if let previewEmail { return previewEmail }
        #endif
        return session.me?.email
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                if let email = accountEmail {
                    accountCard(email: email)
                }

                consequencesCard

                if let errorMessage = model.errorMessage {
                    errorCard(errorMessage)
                }

                deleteButton
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)
        }
        .background(.canvasBackground)
        .navigationTitle("Eliminar cuenta")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(model.isWorking)
        .confirmationDialog(
            "¿Eliminar tu cuenta Aye para siempre?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Eliminar cuenta", role: .destructive) {
                #if DEBUG
                let accountId = session.me?.id ?? (DebugAccount.isActive ? DebugAccount.id : "")
                #else
                let accountId = session.me?.id ?? ""
                #endif
                guard !accountId.isEmpty else { return }
                Task {
                    await model.deleteAyeAccount(accountId: accountId, session: session)
                }
            }
            Button("Cancelar", role: .cancel) {}
        }
    }

    // MARK: - Tarjetas y componentes

    private func accountCard(email: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Cuenta")
                .font(.subheadline)
                .foregroundStyle(.inkMuted)
            Text(email)
                .font(.headline)
                .foregroundStyle(.inkPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .background(.surfaceCard, in: .rect(cornerRadius: Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(.borderLine, lineWidth: 1)
        }
    }

    private var consequencesCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Al eliminar tu cuenta Aye:")
                .font(.headline.weight(.heavy))
                .foregroundStyle(.inkPrimary)

            VStack(alignment: .leading, spacing: Spacing.md) {
                bulletItem("Se borran para siempre tus datos de AyeKitchen, en este teléfono y en tus respaldos.")
                bulletItem("Ya no podrás entrar a ninguna app Aye con esta cuenta.")
                bulletItem("No se puede deshacer.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .background(.surfaceCard, in: .rect(cornerRadius: Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(.borderLine, lineWidth: 1)
        }
    }

    private func bulletItem(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Text("•")
                .font(.body.weight(.bold))
                .foregroundStyle(.inkMuted)
            Text(text)
                .font(.body)
                .foregroundStyle(.inkPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func errorCard(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.warningText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
            .background(.warningSoft, in: .rect(cornerRadius: Radius.control))
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            showingDeleteConfirmation = true
        } label: {
            if model.isWorking {
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                        .tint(.warningText)
                    Text("Eliminando cuenta...")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(.warningText)
                }
                .frame(maxWidth: .infinity, minHeight: minButtonHeight)
            } else {
                Text("Eliminar mi cuenta")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(.warningText)
                    .frame(maxWidth: .infinity, minHeight: minButtonHeight)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .background(.warningSoft, in: .rect(cornerRadius: Radius.primaryButton))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.primaryButton)
                .strokeBorder(.warningText.opacity(0.3), lineWidth: 1)
        }
        .opacity(model.isWorking ? 0.6 : 1)
        .accessibilityLabel(model.isWorking ? "Eliminando cuenta" : "Eliminar mi cuenta")
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Eliminar cuenta - Normal") {
    NavigationStack {
        DeleteAccountView(previewEmail: "alberto@ejemplo.com")
    }
    .environment(SessionStore())
}

#Preview("Eliminar cuenta - AX3") {
    NavigationStack {
        DeleteAccountView(previewEmail: "alberto@ejemplo.com")
    }
    .environment(SessionStore())
    .dynamicTypeSize(.accessibility3)
}

#Preview("Eliminar cuenta - Oscuro") {
    NavigationStack {
        DeleteAccountView(previewEmail: "alberto@ejemplo.com")
    }
    .environment(SessionStore())
    .preferredColorScheme(.dark)
}
#endif
