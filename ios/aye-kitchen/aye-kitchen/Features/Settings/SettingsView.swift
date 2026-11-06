import SwiftUI
import TipKit
import KitchenDomain

/// Pantalla de Cuenta y ajustes (Bloque I21).
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var model: SettingsModel
    @State private var showingSignOutConfirmation = false
    @State private var showingTipsResetAlert = false
    #if DEBUG
    @State private var showingCopiedToast = false
    #endif

    init(store: LocalStore = .shared) {
        self._model = State(initialValue: SettingsModel(store: store))
    }

    init(model: SettingsModel) {
        self._model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            List {
                accountSection
                generalSection
                helpSection
                signOutSection
                #if DEBUG
                debugSection
                #endif
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") {
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                }
            }
            .confirmationDialog(
                "¿Cerrar sesión?",
                isPresented: $showingSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Cerrar sesión", role: .destructive) {
                    Task {
                        await model.signOut(session: session)
                        dismiss()
                    }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Tus datos se quedan en este teléfono. Si tienes cambios sin respaldar, se guardarán antes de salir.")
            }
        }
    }

    // MARK: - Secciones

    // 1. Tu cuenta
    private var accountSection: some View {
        Section("Tu cuenta") {
            if let me = session.me {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(me.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.inkPrimary)
                    Text(me.email)
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)
                }
                .padding(.vertical, Spacing.xs)
            } else {
                Text("Sin sesión activa")
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
            }
        }
    }

    // 2. Respaldo, Tu negocio y Unidades propias
    private var generalSection: some View {
        Section {
            NavigationLink {
                BackupView()
            } label: {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Respaldo")
                            .foregroundStyle(.inkPrimary)
                        Text(model.backupSummaryText)
                            .font(.subheadline)
                            .foregroundStyle(model.isBackupWarning ? .warningText : .inkMuted)
                    }
                } else {
                    HStack(alignment: .center) {
                        Text("Respaldo")
                            .foregroundStyle(.inkPrimary)
                        Spacer()
                        Text(model.backupSummaryText)
                            .font(.subheadline)
                            .foregroundStyle(model.isBackupWarning ? .warningText : .inkMuted)
                    }
                }
            }
            .popoverTip(BackupTip(), arrowEdge: .bottom)

            NavigationLink {
                BusinessSettingsView(store: model.store)
            } label: {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Tu negocio")
                            .foregroundStyle(.inkPrimary)
                        Text(model.businessName)
                            .font(.subheadline)
                            .foregroundStyle(.inkMuted)
                    }
                } else {
                    HStack(alignment: .center) {
                        Text("Tu negocio")
                            .foregroundStyle(.inkPrimary)
                        Spacer()
                        Text(model.businessName)
                            .font(.subheadline)
                            .foregroundStyle(.inkMuted)
                    }
                }
            }

            NavigationLink {
                CustomUnitsView(store: model.store)
            } label: {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Unidades propias")
                            .foregroundStyle(.inkPrimary)
                        Text("\(model.customUnitsCount)")
                            .font(.subheadline)
                            .foregroundStyle(.inkMuted)
                    }
                } else {
                    HStack(alignment: .center) {
                        Text("Unidades propias")
                            .foregroundStyle(.inkPrimary)
                        Spacer()
                        Text("\(model.customUnitsCount)")
                            .font(.subheadline)
                            .foregroundStyle(.inkMuted)
                    }
                }
            }
        }
    }

    // 3. Ayuda
    private var helpSection: some View {
        Section {
            Button {
                KitchenTips.requestResetOnNextLaunch()
                showingTipsResetAlert = true
            } label: {
                Text("Volver a ver los consejos")
                    .foregroundStyle(.inkPrimary)
            }
            .alert("Consejos", isPresented: $showingTipsResetAlert) {
                Button("Entendido", role: .cancel) {}
            } message: {
                Text("Los verás otra vez la próxima vez que abras la app.")
            }
        } header: {
            Text("Ayuda")
        } footer: {
            Text("Los verás otra vez la próxima vez que abras la app.")
        }
    }

    // 4. Cerrar sesión
    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                showingSignOutConfirmation = true
            } label: {
                if model.isSigningOut {
                    HStack(spacing: Spacing.sm) {
                        ProgressView()
                            .tint(.warningText)
                        Text("Cerrando sesión...")
                            .foregroundStyle(.warningText)
                    }
                } else {
                    Text("Cerrar sesión")
                        .foregroundStyle(.warningText)
                }
            }
            .disabled(model.isSigningOut)
        }
    }

    // 4. Sección de desarrollo (DEBUG)
    #if DEBUG
    private var debugSection: some View {
        Section("Desarrollo") {
            Button {
                model.copySessionForScripts()
                showingCopiedToast = true
            } label: {
                Label("Copiar sesión (DEBUG)", systemImage: "doc.on.clipboard")
                    .foregroundStyle(.tint)
            }
            .alert("Sesión copiada", isPresented: $showingCopiedToast) {
                Button("Aceptar", role: .cancel) {}
            } message: {
                Text("Los tokens se copiaron al portapapeles universal.")
            }
        }
    }
    #endif
}

// MARK: - Previews

#if DEBUG
#Preview("Ajustes - Normal") {
    SettingsView(model: .preview())
        .environment(SessionStore())
}

#Preview("Ajustes - Con cambios sin respaldar") {
    SettingsView(model: .preview(hasUnbackedChanges: true))
        .environment(SessionStore())
}

#Preview("Ajustes - Accesibilidad") {
    SettingsView(model: .preview())
        .environment(SessionStore())
        .dynamicTypeSize(.accessibility3)
}
#endif
