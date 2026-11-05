import SwiftUI
import KitchenDomain

/// Hoja para crear o editar un cliente (Bloque I18 local-first).
struct CustomerFormView: View {
    @Environment(\.dismiss) private var dismiss

    private let customerId: String?
    private let store: LocalStore
    private let onSave: ((Customer) -> Void)?

    @State private var name: String
    @State private var phone: String
    @State private var notes: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        customerId: String? = nil,
        initialName: String = "",
        store: LocalStore = .shared,
        onSave: ((Customer) -> Void)? = nil
    ) {
        self.customerId = customerId
        self.store = store
        self.onSave = onSave

        if let customerId, let existing = try? store.data.customer(id: customerId) {
            self._name = State(initialValue: existing.name)
            self._phone = State(initialValue: existing.phone ?? "")
            self._notes = State(initialValue: existing.notes ?? "")
        } else {
            self._name = State(initialValue: initialName)
            self._phone = State(initialValue: "")
            self._notes = State(initialValue: "")
        }
    }

    init(
        customer: Customer?,
        store: LocalStore = .shared,
        onSave: ((Customer) -> Void)? = nil
    ) {
        self.init(
            customerId: customer?.id,
            initialName: customer?.name ?? "",
            store: store,
            onSave: onSave
        )
    }

    private var isEditing: Bool {
        customerId != nil
    }

    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= 1 && trimmed.count <= 120 && !isSaving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    inputFields

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.warningText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Spacing.md)
                            .background(.warningSoft, in: .rect(cornerRadius: Radius.control))
                    }

                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(.accentInk)
                        } else {
                            Text("Guardar cliente")
                        }
                    }
                    .buttonStyle(.kitchenPrimary)
                    .disabled(!canSave)
                }
                .padding(Spacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(.canvasBackground)
            .navigationTitle(isEditing ? "Editar cliente" : "Nuevo cliente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                    .font(.body)
                    .foregroundStyle(.tint)
                }
            }
        }
    }

    private var inputFields: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            KitchenTextField(
                label: "Nombre",
                text: $name,
                contentType: .name,
                capitalization: .words
            )

            KitchenTextField(
                label: "Teléfono",
                text: $phone,
                keyboard: .phonePad,
                contentType: .telephoneNumber
            )

            VStack(alignment: .leading, spacing: Spacing.xs) {
                KitchenTextField(
                    label: "Notas",
                    text: $notes
                )
                Text("Ej. Le gusta poco dulce, recoge en la tarde")
                    .font(.footnote)
                    .foregroundStyle(.inkMuted)
                    .padding(.horizontal, Spacing.xs)
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard trimmedName.count >= 1 && trimmedName.count <= 120 else { return }

        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        let phoneToSend = trimmedPhone.isEmpty ? nil : trimmedPhone

        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)
        let notesToSend = trimmedNotes.isEmpty ? nil : trimmedNotes

        isSaving = true
        errorMessage = nil

        do {
            let result: Customer
            if let customerId {
                result = try store.mutate { data, ctx in
                    try data.updateCustomer(
                        id: customerId,
                        name: trimmedName,
                        phone: phoneToSend,
                        notes: notesToSend,
                        ctx: ctx
                    )
                }
            } else {
                result = try store.mutate { data, ctx in
                    try data.createCustomer(
                        name: trimmedName,
                        phone: phoneToSend,
                        notes: notesToSend,
                        ctx: ctx
                    )
                }
            }
            isSaving = false
            onSave?(result)
            dismiss()
        } catch let domainError as DomainError {
            isSaving = false
            if domainError.code == "DUPLICATE_NAME" {
                errorMessage = "Ya tienes un cliente con ese nombre."
            } else {
                errorMessage = domainError.detail
            }
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
        }
    }
}

#if DEBUG
#Preview("Nuevo cliente") {
    CustomerFormView(store: .preview())
}

#Preview("Editar cliente") {
    CustomerFormView(customerId: "cus-ana", store: .preview())
}
#endif
