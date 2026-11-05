import SwiftUI

/// Modo de operación para la hoja de nombre de versión.
enum CostVersionNameMode: Sendable {
    case create
    case rename(versionId: String, currentName: String)

    var title: String {
        switch self {
        case .create: "Nueva versión"
        case .rename: "Cambiar nombre"
        }
    }

    var actionButtonTitle: String {
        switch self {
        case .create: "Crear versión"
        case .rename: "Guardar cambios"
        }
    }
}

/// Hoja para crear o renombrar una versión de costeo (Bloque I10).
struct CostVersionNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let mode: CostVersionNameMode
    let onSave: @MainActor @Sendable (String) async throws -> Void

    @State private var name: String
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil

    init(
        mode: CostVersionNameMode,
        onSave: @escaping @MainActor @Sendable (String) async throws -> Void
    ) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .create:
            _name = State(initialValue: "")
        case .rename(_, let currentName):
            _name = State(initialValue: currentName)
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        KitchenTextField(
                            label: "Nombre de la versión",
                            text: $name
                        )

                        Text("Ej. Con Selecta, Con Tres Estrellas")
                            .font(.footnote)
                            .foregroundStyle(.inkMuted)
                            .padding(.horizontal, Spacing.xs)
                    }

                    if let errorMessage {
                        HStack(alignment: .top, spacing: Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.warningText)
                                .accessibilityHidden(true)
                            Text(errorMessage)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.warningText)
                        }
                        .padding(Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.warningSoft, in: .rect(cornerRadius: Radius.control))
                    }

                    Button {
                        submit()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(.accentInk)
                        } else {
                            Text(mode.actionButtonTitle)
                        }
                    }
                    .buttonStyle(.kitchenPrimary)
                    .disabled(!canSave)
                }
                .padding(Spacing.xl)
            }
            .background(.canvasBackground)
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
                }
            }
        }
    }

    private func submit() {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await onSave(trimmedName)
                dismiss()
            } catch let apiError as APIError {
                if apiError.code == "DUPLICATE_NAME" {
                    errorMessage = "Ya tienes una versión con ese nombre"
                } else {
                    errorMessage = apiError.localizedDescription
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

#if DEBUG
#Preview("Crear versión — Normal") {
    CostVersionNameSheet(mode: .create) { _ in }
}

#Preview("Crear versión — Letra AX3") {
    CostVersionNameSheet(mode: .create) { _ in }
        .dynamicTypeSize(.accessibility3)
}

#Preview("Renombrar versión — Normal") {
    CostVersionNameSheet(mode: .rename(versionId: "v1", currentName: "Con Tres Estrellas")) { _ in }
}
#endif
