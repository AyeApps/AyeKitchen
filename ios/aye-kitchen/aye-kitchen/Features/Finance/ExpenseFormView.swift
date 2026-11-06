import SwiftUI
import KitchenDomain

/// Hoja para registrar o editar un gasto (Bloque I22 local-first).
struct ExpenseFormView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isAmountFocused: Bool

    private let expenseId: String?
    private let store: LocalStore
    private let onSave: ((Expense) -> Void)?

    @State private var descriptionText: String
    @State private var amountText: String
    @State private var spentAt: Date
    @State private var categoryText: String
    @State private var selectedSupplierId: String?

    @State private var descriptionError: String?
    @State private var amountError: String?
    @State private var generalError: String?
    @State private var isSaving: Bool = false

    init(
        expense: Expense? = nil,
        store: LocalStore = .shared,
        onSave: ((Expense) -> Void)? = nil
    ) {
        self.expenseId = expense?.id
        self.store = store
        self.onSave = onSave

        if let expense {
            self._descriptionText = State(initialValue: expense.description)
            self._amountText = State(initialValue: CurrencyMath.formatForInput(cents: expense.amountCents))
            self._spentAt = State(initialValue: expense.spentAt)
            self._categoryText = State(initialValue: expense.category ?? "")
            self._selectedSupplierId = State(initialValue: expense.supplierId)
        } else {
            self._descriptionText = State(initialValue: "")
            self._amountText = State(initialValue: "")
            self._spentAt = State(initialValue: Date())
            self._categoryText = State(initialValue: "")
            self._selectedSupplierId = State(initialValue: nil)
        }
    }

    private var isEditing: Bool {
        expenseId != nil
    }

    private var suggestedCategories: [String] {
        store.data.expenseCategories()
    }

    private var suppliers: [Supplier] {
        store.data.activeSuppliers()
    }

    private var selectedSupplierName: String? {
        guard let id = selectedSupplierId else { return nil }
        return suppliers.first(where: { $0.id == id })?.name
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        descriptionSection
                        amountSection
                        dateSection
                        categorySection
                        supplierSection
                    }

                    if let generalError {
                        Label(generalError, systemImage: "exclamationmark.triangle.fill")
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
                            Text(isEditing ? "Guardar cambios" : "Guardar gasto")
                        }
                    }
                    .buttonStyle(.kitchenPrimary)
                    .disabled(isSaving)
                }
                .padding(Spacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(.canvasBackground)
            .navigationTitle(isEditing ? "Editar gasto" : "Nuevo gasto")
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

    // MARK: - Campos

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            KitchenTextField(
                label: "Descripción",
                text: $descriptionText,
                capitalization: .sentences
            )
            .onChange(of: descriptionText) { _, newValue in
                if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    descriptionError = nil
                }
            }

            if let descriptionError {
                Text(descriptionError)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.warningText)
                    .padding(.horizontal, Spacing.xs)
            }
        }
    }

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Monto")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.inkPrimary)
                    .accessibilityHidden(true)

                HStack(spacing: Spacing.xs) {
                    Text("$")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.inkSecondary)

                    TextField("0.00", text: $amountText)
                        .font(.body)
                        .foregroundStyle(.inkPrimary)
                        .keyboardType(.decimalPad)
                        .focused($isAmountFocused)
                        .onChange(of: amountText) { _, newValue in
                            if let cents = CurrencyMath.parseCents(from: newValue), cents > 0 {
                                amountError = nil
                            }
                        }
                }
                .padding(.horizontal, 18)
                .frame(minHeight: 56)
                .background(.surfaceInput, in: .rect(cornerRadius: Radius.card))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.card)
                        .strokeBorder(isAmountFocused ? Color.accentColor : Color.borderInput, lineWidth: isAmountFocused ? 2 : 1.5)
                }
                .accessibilityLabel("Monto")
            }

            if let amountError {
                Text(amountError)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.warningText)
                    .padding(.horizontal, Spacing.xs)
            }
        }
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Fecha")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.inkPrimary)

            HStack {
                DatePicker(
                    "Fecha del gasto",
                    selection: $spentAt,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "es_MX"))

                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 56)
            .background(.surfaceInput, in: .rect(cornerRadius: Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(Color.borderInput, lineWidth: 1.5)
            }
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            KitchenTextField(
                label: "Categoría (opcional)",
                text: $categoryText,
                capitalization: .words
            )

            if !suggestedCategories.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Categorías usadas:")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.inkMuted)
                        .padding(.horizontal, Spacing.xs)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.sm) {
                            ForEach(suggestedCategories, id: \.self) { cat in
                                Button {
                                    categoryText = cat
                                } label: {
                                    Text(cat)
                                        .font(.footnote.weight(.bold))
                                        .foregroundStyle(categoryText == cat ? .accentTextDeep : .inkPrimary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(categoryText == cat ? .accentSoftStrong : .neutralSoft, in: .capsule)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.top, Spacing.xs)
            }
        }
    }

    private var supplierSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Proveedor (opcional)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.inkPrimary)

            Menu {
                Button("Ninguno") {
                    selectedSupplierId = nil
                }
                ForEach(suppliers) { sup in
                    Button(sup.name) {
                        selectedSupplierId = sup.id
                    }
                }
            } label: {
                HStack {
                    Text(selectedSupplierName ?? "Elegir proveedor")
                        .font(.body)
                        .foregroundStyle(selectedSupplierId != nil ? .inkPrimary : .inkMuted)

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.inkMuted)
                }
                .padding(.horizontal, 18)
                .frame(minHeight: 56)
                .background(.surfaceInput, in: .rect(cornerRadius: Radius.card))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.card)
                        .strokeBorder(Color.borderInput, lineWidth: 1.5)
                }
            }
            .accessibilityLabel("Proveedor: \(selectedSupplierName ?? "ninguno")")
        }
    }

    // MARK: - Guardado

    private func save() {
        descriptionError = nil
        amountError = nil
        generalError = nil

        let trimmedDesc = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDesc.isEmpty {
            descriptionError = "La descripción es obligatoria"
        }

        let parsedCents = CurrencyMath.parseCents(from: amountText)
        if parsedCents == nil || (parsedCents ?? 0) <= 0 {
            amountError = "El monto debe ser mayor que cero"
        }

        guard descriptionError == nil, let cents = parsedCents, cents > 0 else {
            return
        }

        let cleanCat = categoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let categoryToSend: String? = cleanCat.isEmpty ? nil : cleanCat

        isSaving = true

        do {
            let savedExpense: Expense
            if let expenseId {
                savedExpense = try store.mutate { data, ctx in
                    try data.updateExpense(
                        id: expenseId,
                        description: trimmedDesc,
                        amountCents: cents,
                        spentAt: spentAt,
                        category: .some(categoryToSend),
                        supplierId: .some(selectedSupplierId),
                        ctx: ctx
                    )
                }
            } else {
                savedExpense = try store.mutate { data, ctx in
                    try data.createExpense(
                        description: trimmedDesc,
                        amountCents: cents,
                        spentAt: spentAt,
                        category: categoryToSend,
                        supplierId: selectedSupplierId,
                        ctx: ctx
                    )
                }
            }
            isSaving = false
            onSave?(savedExpense)
            dismiss()
        } catch let domainError as DomainError {
            isSaving = false
            if domainError.code == "INVALID_VALUE" {
                if domainError.detail.localizedCaseInsensitiveContains("descripción") {
                    descriptionError = domainError.detail
                } else if domainError.detail.localizedCaseInsensitiveContains("monto") {
                    amountError = domainError.detail
                } else {
                    generalError = domainError.detail
                }
            } else {
                generalError = domainError.detail
            }
        } catch {
            isSaving = false
            generalError = error.localizedDescription
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Nuevo gasto") {
    ExpenseFormView(store: .preview())
}

#Preview("Nuevo gasto — AX3") {
    ExpenseFormView(store: .preview())
        .dynamicTypeSize(.accessibility3)
}

#Preview("Editar gasto") {
    let store = LocalStore.preview()
    let expense = Expense(
        id: "exp-1",
        description: "Harina de trigo 10 kg",
        amountCents: 18500,
        spentAt: Date(),
        category: "Insumos",
        supplierId: "sup-walmart",
        createdAt: Date(),
        updatedAt: Date()
    )
    return ExpenseFormView(expense: expense, store: store)
}
#endif
