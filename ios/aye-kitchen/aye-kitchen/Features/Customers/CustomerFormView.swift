import SwiftUI

// MARK: - Cuerpos de petición (docs/api-contract.md)

nonisolated struct CustomerCreateRequest: Encodable, Sendable {
    let name: String
    let phone: String?
    let notes: String?
}

nonisolated struct CustomerUpdateRequest: Encodable, Sendable {
    let name: String
    let phone: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case name, phone, notes
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        if let phone {
            try container.encode(phone, forKey: .phone)
        } else {
            try container.encodeNil(forKey: .phone)
        }
        if let notes {
            try container.encode(notes, forKey: .notes)
        } else {
            try container.encodeNil(forKey: .notes)
        }
    }
}

// MARK: - Vista de Formulario de Cliente

/// Hoja para crear o editar un cliente según Bloque I7a.
struct CustomerFormView: View {
    @Environment(\.dismiss) private var dismiss

    private let customer: Customer?
    private let isMock: Bool
    private let onSave: (Customer) -> Void

    @State private var name: String
    @State private var phone: String
    @State private var notes: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        customer: Customer? = nil,
        initialName: String = "",
        isMock: Bool = false,
        onSave: @escaping (Customer) -> Void
    ) {
        self.customer = customer
        self.isMock = isMock
        self.onSave = onSave
        self._name = State(initialValue: customer?.name ?? initialName)
        self._phone = State(initialValue: customer?.phone ?? "")
        self._notes = State(initialValue: customer?.notes ?? "")
    }

    private var isEditing: Bool {
        customer != nil
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
                        Task { await save() }
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

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard trimmedName.count >= 1 && trimmedName.count <= 120 else { return }

        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        let phoneToSend = trimmedPhone.isEmpty ? nil : trimmedPhone

        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)
        let notesToSend = trimmedNotes.isEmpty ? nil : trimmedNotes

        if isMock || customer?.id.hasPrefix("mock") == true {
            let saved = Customer(
                id: customer?.id ?? "mock_\(UUID().uuidString.prefix(6))",
                name: trimmedName,
                phone: phoneToSend,
                notes: notesToSend,
                createdAt: customer?.createdAt ?? Date(),
                updatedAt: Date()
            )
            onSave(saved)
            dismiss()
            return
        }

        isSaving = true
        errorMessage = nil

        do {
            let result: Customer
            if let customer {
                let body = CustomerUpdateRequest(name: trimmedName, phone: phoneToSend, notes: notesToSend)
                result = try await NetworkService.shared.request(
                    .patch,
                    "/customers/\(customer.id)",
                    body: body
                )
            } else {
                let body = CustomerCreateRequest(name: trimmedName, phone: phoneToSend, notes: notesToSend)
                result = try await NetworkService.shared.request(
                    .post,
                    "/customers/",
                    body: body
                )
            }
            isSaving = false
            onSave(result)
            dismiss()
        } catch let apiError as APIError {
            isSaving = false
            if apiError.code == "DUPLICATE_NAME" {
                errorMessage = "Ya tienes un cliente con ese nombre."
            } else {
                errorMessage = apiError.localizedDescription
            }
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Previews

#if DEBUG
private let mockCustomerForEdit = Customer(
    id: "mock_edit_1",
    name: "Ana Ruiz",
    phone: "55 1234 5678",
    notes: "Le gusta poco dulce, recoge en la tarde",
    createdAt: Date(),
    updatedAt: Date()
)

#Preview("Nuevo cliente") {
    CustomerFormView(isMock: true) { _ in }
}

#Preview("Editar cliente") {
    CustomerFormView(customer: mockCustomerForEdit, isMock: true) { _ in }
}

#Preview("Letra AX3") {
    CustomerFormView(customer: mockCustomerForEdit, isMock: true) { _ in }
        .dynamicTypeSize(.accessibility3)
}
#endif
