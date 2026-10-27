import SwiftUI

/// Formulario para crear o editar un pedido según Bloque I2.
struct OrderFormView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var model: OrderFormModel
    @State private var showingRecipePicker = false
    let onSave: @MainActor @Sendable (Order) -> Void

    init(order: Order? = nil, onSave: @escaping @MainActor @Sendable (Order) -> Void) {
        _model = State(initialValue: OrderFormModel(order: order))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    inputFields
                    cakesSection

                    if let errorMessage = model.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.warningText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Spacing.md)
                            .background(.warningSoft, in: .rect(cornerRadius: Radius.control))
                    }

                    Button {
                        Task { await saveOrder() }
                    } label: {
                        if model.isSaving {
                            ProgressView()
                                .tint(.accentInk)
                        } else {
                            Text("Guardar pedido")
                        }
                    }
                    .buttonStyle(.kitchenPrimary)
                    .disabled(!model.canSave)
                }
                .padding(Spacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(.canvasBackground)
            .navigationTitle(model.isEditing ? "Editar pedido" : "Nuevo pedido")
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
            .sheet(isPresented: $showingRecipePicker) {
                RecipePickerSheet { selectedRecipe in
                    Task {
                        await model.addRecipe(selectedRecipe)
                    }
                }
            }
        }
    }

    private var inputFields: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            KitchenTextField(
                label: "Cliente",
                text: $model.customerName
            )

            KitchenTextField(
                label: "Teléfono",
                text: $model.customerPhone,
                keyboard: .phonePad
            )

            deliveryDatePicker

            KitchenTextField(
                label: "Notas",
                text: $model.notes
            )
        }
    }

    private var deliveryDatePicker: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Entrega")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.inkPrimary)

            DatePicker(
                "",
                selection: $model.deliveryAt,
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .environment(\.locale, Locale(identifier: "es_MX"))
            .padding(.horizontal, 18)
            .frame(minHeight: 56)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.surfaceInput, in: .rect(cornerRadius: Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(Color.borderInput, lineWidth: 1.5)
            }
            .accessibilityLabel("Fecha y hora de entrega")
        }
    }

    private var cakesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Pasteles")
                .sectionTitleStyle()

            if model.items.isEmpty {
                Text("Agrega al menos un pastel al pedido.")
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
            } else {
                RowGroup {
                    ForEach($model.items) { $item in
                        cakeItemRow(item: $item)
                    }
                }
            }

            Button {
                showingRecipePicker = true
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "plus")
                        .font(.body.weight(.bold))
                    Text("Agregar pastel")
                        .font(.body.weight(.bold))
                }
                .foregroundStyle(.tint)
                .padding(.vertical, Spacing.xs)
            }
        }
    }

    private func cakeItemRow(item: Binding<DraftOrderItem>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .center) {
                Text(item.wrappedValue.recipeName)
                    .font(.headline)
                    .foregroundStyle(.inkPrimary)
                Spacer()
                Button(role: .destructive) {
                    model.removeItem(id: item.wrappedValue.id)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.inkMuted)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Quitar \(item.wrappedValue.recipeName)")
            }

            HStack {
                Text("Cantidad: \(Quantity.format(item.wrappedValue.quantityString))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.inkPrimary)
                Spacer()
                Stepper(
                    "",
                    onIncrement: {
                        item.wrappedValue.quantity += 1
                    },
                    onDecrement: item.wrappedValue.quantity < 1 ? nil : {
                        item.wrappedValue.quantity = max(1, item.wrappedValue.quantity - 1)
                    }
                )
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                KitchenTextField(
                    label: "Precio por unidad",
                    text: item.unitPriceText,
                    keyboard: .decimalPad
                )

                if let suggested = item.wrappedValue.suggestedPriceCents {
                    Text("Te sugerimos cobrar \(Money.format(cents: suggested))")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tint)
                } else if item.wrappedValue.costCalculationFailed {
                    Text("No pudimos calcular el precio sugerido. Escribe cuánto vas a cobrar.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.warningText)
                }
            }
        }
        .padding(Spacing.lg)
    }

    private func saveOrder() async {
        do {
            let saved = try await model.save()
            onSave(saved)
            dismiss()
        } catch {
            // El error ya se procesa y muestra en model.errorMessage
        }
    }
}

/// Hoja para buscar y seleccionar una receta del catálogo.
struct RecipePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSelect: (RecipeListItem) -> Void

    @State private var model: RecipePickerModel

    init(model: RecipePickerModel = RecipePickerModel(), onSelect: @escaping (RecipeListItem) -> Void) {
        _model = State(initialValue: model)
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            content
                .background(.canvasBackground)
                .navigationTitle("Pasteles")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $model.query, prompt: "Buscar receta")
                .onChange(of: model.query) { _, _ in
                    Task { await model.searchRecipes() }
                }
                .task {
                    await model.searchRecipes()
                }
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

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.recipes.isEmpty {
            ProgressView()
                .tint(.accentInk)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = model.errorMessage, model.recipes.isEmpty {
            ErrorStateView(message: errorMessage) {
                Task { await model.searchRecipes() }
            }
        } else if model.recipes.isEmpty {
            ContentUnavailableView(
                "No hay recetas",
                systemImage: "magnifyingglass",
                description: Text("No se encontraron recetas con ese nombre.")
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    RowGroup {
                        ForEach(model.recipes) { item in
                            Button {
                                select(item)
                            } label: {
                                HStack(spacing: Spacing.md) {
                                    VStack(alignment: .leading, spacing: Spacing.xs) {
                                        Text(item.recipe.name)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(.inkPrimary)
                                    }

                                    Spacer()

                                    if !item.complete {
                                        Chip("Falta precio", tone: .warning)
                                    }

                                    if model.selectingId == item.id {
                                        ProgressView()
                                            .tint(.accentInk)
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(.inkMuted)
                                    }
                                }
                                .padding(Spacing.lg)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(model.selectingId != nil)
                        }
                    }
                }
                .padding(Spacing.xl)
            }
        }
    }

    private func select(_ item: RecipeListItem) {
        model.selectingId = item.id
        onSelect(item)
        dismiss()
    }
}

#if DEBUG
#Preview("Nuevo pedido — Claro") {
    OrderFormView(order: nil) { _ in }
}

#Preview("Nuevo pedido — Letra AX3") {
    OrderFormView(order: nil) { _ in }
        .dynamicTypeSize(.accessibility3)
}

#Preview("Editar pedido — Claro") {
    OrderFormView(order: .mockPendingToday) { _ in }
}

#Preview("Selector de receta") {
    RecipePickerSheet(
        model: RecipePickerModel(recipes: [.mockChocolate, .mockVainilla, .mockIncomplete])
    ) { _ in }
}
#endif
