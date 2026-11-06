import SwiftUI

/// Pantalla de Respaldo de AyeKitchen (Bloque I20).
struct BackupView: View {
    @State private var model: BackupModel
    @State private var showingRestoreConfirmation = false
    @State private var showingUseLocalConfirmation = false
    @State private var showingBringRemoteConfirmation = false

    init(model: BackupModel = BackupModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.section) {
                    stateCard

                    if model.hasConflict {
                        conflictCard
                    }

                    actionsSection
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.lg)
            }
            .background(Color.canvasBackground.ignoresSafeArea())
            .navigationTitle("Respaldo")
            .refreshable {
                await model.refresh()
            }
            .task {
                await model.loadLatestInfo()
            }
            .alert(
                "¿Restaurar el último respaldo?",
                isPresented: $showingRestoreConfirmation
            ) {
                Button("Restaurar", role: .destructive) {
                    Task {
                        await model.restoreLatest()
                    }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text(model.restoreConfirmationAttributedString)
            }
            .alert(
                "¿Usar los datos de este teléfono?",
                isPresented: $showingUseLocalConfirmation
            ) {
                Button("Usar datos de este teléfono", role: .destructive) {
                    Task {
                        await model.resolveConflictUsingLocal()
                    }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Esto sobrescribirá el respaldo en el servidor con lo que hay actualmente en este teléfono.")
            }
            .alert(
                "¿Traer los datos del otro respaldo?",
                isPresented: $showingBringRemoteConfirmation
            ) {
                Button("Traer respaldo", role: .destructive) {
                    Task {
                        await model.resolveConflictRestoringRemote()
                    }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text(model.bringRemoteConfirmationAttributedString)
            }
            .alert(
                "No se pudo restaurar",
                isPresented: Binding(
                    get: { model.restoreErrorMessage != nil },
                    set: { if !$0 { model.restoreErrorMessage = nil } }
                )
            ) {
                Button("Aceptar", role: .cancel) {}
            } message: {
                if let message = model.restoreErrorMessage {
                    Text(message)
                }
            }
        }
    }

    // MARK: Tarjeta de estado

    private var stateCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(model.lastBackupSummary)
                .font(.title3.weight(.heavy))
                .foregroundStyle(.inkPrimary)

            if model.hasUnbackedChanges {
                Text("Tienes cambios sin respaldar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.warningText)
            } else {
                Text("Todo está respaldado")
                    .font(.subheadline)
                    .foregroundStyle(.inkSecondary)
            }

            if let failedText = model.failedErrorText {
                Text(failedText)
                    .font(.subheadline)
                    .foregroundStyle(.warningText)
                    .padding(.top, Spacing.xs)
            }
        }
        .softCard()
    }

    // MARK: Tarjeta de conflicto

    private var conflictCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.warningText)

                Text("Otro teléfono guardó un respaldo más nuevo")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(.warningText)
            }

            if let detail = model.conflictDetail {
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.inkPrimary)
            }

            VStack(spacing: Spacing.md) {
                Button {
                    showingUseLocalConfirmation = true
                } label: {
                    Text("Usar los datos de este teléfono")
                }
                .buttonStyle(.kitchenSecondary)
                .disabled(model.isBusy)

                Button {
                    showingBringRemoteConfirmation = true
                } label: {
                    Text("Traer los datos del otro respaldo")
                }
                .buttonStyle(.kitchenSecondary)
                .disabled(model.isBusy)
            }
            .padding(.top, Spacing.xs)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.warningSoft, in: .rect(cornerRadius: Radius.card))
    }

    // MARK: Acciones principales

    private var actionsSection: some View {
        VStack(spacing: Spacing.md) {
            Button {
                Task {
                    await model.backupNow()
                }
            } label: {
                if model.isBackingUpEffective {
                    HStack(spacing: Spacing.sm) {
                        ProgressView()
                            .tint(.accentInk)
                        Text("Respaldando...")
                    }
                } else {
                    Text("Respaldar ahora")
                }
            }
            .buttonStyle(.kitchenPrimary)
            .disabled(model.isBusy || model.hasConflict)

            Button {
                showingRestoreConfirmation = true
            } label: {
                if model.isRestoring {
                    HStack(spacing: Spacing.sm) {
                        ProgressView()
                            .tint(.inkPrimary)
                        Text("Restaurando...")
                    }
                } else {
                    Text("Restaurar el último respaldo")
                }
            }
            .buttonStyle(.kitchenSecondary)
            .disabled(model.isBusy)
        }
    }
}

// MARK: Previews

#if DEBUG
#Preview("Todo respaldado") {
    BackupView(model: .preview(
        lastBackupAt: Date(),
        hasUnbackedChanges: false,
        lastError: nil
    ))
}

#Preview("Todo respaldado - Accesibilidad") {
    BackupView(model: .preview(
        lastBackupAt: Date(),
        hasUnbackedChanges: false,
        lastError: nil
    ))
    .dynamicTypeSize(.accessibility3)
}

#Preview("Con cambios sin respaldar") {
    BackupView(model: .preview(
        lastBackupAt: Calendar.current.date(byAdding: .minute, value: -45, to: Date()),
        hasUnbackedChanges: true,
        lastError: nil
    ))
}

#Preview("Con cambios sin respaldar - Accesibilidad") {
    BackupView(model: .preview(
        lastBackupAt: Calendar.current.date(byAdding: .minute, value: -45, to: Date()),
        hasUnbackedChanges: true,
        lastError: nil
    ))
    .dynamicTypeSize(.accessibility3)
}

#Preview("Con conflicto") {
    BackupView(model: .preview(
        lastBackupAt: Calendar.current.date(byAdding: .hour, value: -3, to: Date()),
        hasUnbackedChanges: true,
        lastError: .conflict("Otro teléfono guardó un respaldo hoy a las 5:10 pm")
    ))
}

#Preview("Con conflicto - Accesibilidad") {
    BackupView(model: .preview(
        lastBackupAt: Calendar.current.date(byAdding: .hour, value: -3, to: Date()),
        hasUnbackedChanges: true,
        lastError: .conflict("Otro teléfono guardó un respaldo hoy a las 5:10 pm")
    ))
    .dynamicTypeSize(.accessibility3)
}
#endif
