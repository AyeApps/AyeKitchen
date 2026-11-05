import SwiftUI

/// Formulario para crear o editar un pedido según Bloque I2.
struct OrderFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var model: OrderFormModel
    @State private var showingRecipePicker = false
    @State private var showingCustomerPicker = false
    let onSave: @MainActor @Sendable (RemoteOrder) -> Void

    init(order: RemoteOrder? = nil, onSave: @escaping @MainActor @Sendable (RemoteOrder) -> Void) {
        _model = State(initialValue: OrderFormModel(order: order))
        self.onSave = onSave
    }

#if DEBUG
    init(model: OrderFormModel, onSave: @escaping @MainActor @Sendable (RemoteOrder) -> Void = { _ in }) {
        _model = State(initialValue: model)
        self.onSave = onSave
    }
#endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    inputFields
                    productsSection

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
            .sheet(isPresented: $showingCustomerPicker) {
                CustomerPickerSheet { selectedCustomer in
                    model.selectCustomer(selectedCustomer)
                }
            }
            .task {
                await model.loadRecipeDetailsForEditing()
            }
        }
    }

    private var inputFields: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            customerPickerField

            deliveryDatePicker

            KitchenTextField(
                label: "Notas",
                text: $model.notes
            )
        }
    }

    private var customerPickerField: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Cliente")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.inkPrimary)

            Button {
                showingCustomerPicker = true
            } label: {
                HStack(spacing: Spacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        if model.customerId != nil {
                            Text(model.customerName)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.inkPrimary)
                            if !model.customerPhone.trimmingCharacters(in: .whitespaces).isEmpty {
                                Text(model.customerPhone)
                                    .font(.subheadline)
                                    .foregroundStyle(.inkMuted)
                            }
                        } else if !model.customerName.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text(model.customerName)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.inkPrimary)
                            Text("Sin guardar en Clientes")
                                .font(.subheadline)
                                .foregroundStyle(.inkMuted)
                        } else {
                            Text("Elige un cliente")
                                .font(.body)
                                .foregroundStyle(.inkMuted)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.inkMuted)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, Spacing.sm)
                .frame(minHeight: 56)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.surfaceInput, in: .rect(cornerRadius: Radius.card))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.card)
                        .strokeBorder(Color.borderInput, lineWidth: 1.5)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(customerFieldAccessibilityLabel)
        }
    }

    private var customerFieldAccessibilityLabel: String {
        if model.customerId != nil {
            if !model.customerPhone.trimmingCharacters(in: .whitespaces).isEmpty {
                return "Cliente: \(model.customerName), teléfono: \(model.customerPhone)"
            }
            return "Cliente: \(model.customerName)"
        } else if !model.customerName.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Cliente: \(model.customerName), sin guardar en Clientes"
        } else {
            return "Elige un cliente"
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

    private var productsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Productos")
                .sectionTitleStyle()

            if model.items.isEmpty {
                Text("Agrega al menos un producto al pedido.")
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
            } else {
                RowGroup {
                    ForEach($model.items) { $item in
                        productItemRow(item: $item)
                    }
                }
            }

            Button {
                showingRecipePicker = true
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "plus")
                        .font(.body.weight(.bold))
                    Text("Agregar producto")
                        .font(.body.weight(.bold))
                }
                .foregroundStyle(.tint)
                .padding(.vertical, Spacing.xs)
            }
        }
    }

    private func productItemRow(item: Binding<DraftOrderItem>) -> some View {
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

            // Selector por unidad / por tanda (solo si la receta rinde más de 1)
            if item.wrappedValue.yieldsMultiple {
                Picker("Modo de venta", selection: Binding(
                    get: { item.wrappedValue.soldBy },
                    set: { item.wrappedValue.changeMode(to: $0) }
                )) {
                    Text(item.wrappedValue.unitOptionTitle).tag(RemoteOrderSoldBy.unit)
                    Text("Por tanda").tag(RemoteOrderSoldBy.batch)
                }
                .pickerStyle(.segmented)
            }

            // Cantidad
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        KitchenTextField(
                            label: item.wrappedValue.quantityLabel,
                            text: item.quantityText,
                            keyboard: .decimalPad
                        )

                        HStack {
                            Spacer()
                            Stepper(
                                "Cantidad de \(item.wrappedValue.recipeName)",
                                onIncrement: {
                                    item.wrappedValue.incrementQuantity()
                                },
                                onDecrement: item.wrappedValue.canDecrementQuantity ? {
                                    item.wrappedValue.decrementQuantity()
                                } : nil
                            )
                            .labelsHidden()
                        }
                    }
                } else {
                    HStack(alignment: .bottom, spacing: Spacing.md) {
                        KitchenTextField(
                            label: item.wrappedValue.quantityLabel,
                            text: item.quantityText,
                            keyboard: .decimalPad
                        )

                        Stepper(
                            "Cantidad de \(item.wrappedValue.recipeName)",
                            onIncrement: {
                                item.wrappedValue.incrementQuantity()
                            },
                            onDecrement: item.wrappedValue.canDecrementQuantity ? {
                                item.wrappedValue.decrementQuantity()
                            } : nil
                        )
                        .labelsHidden()
                        .padding(.bottom, 8)
                    }
                }

                if item.wrappedValue.isQuantityInvalid {
                    Text("Escribe una cantidad mayor a 0.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.warningText)
                } else if item.wrappedValue.soldBy == .batch, let summary = item.wrappedValue.yieldSummary {
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(.inkMuted)
                }
            }

            // Precio
            VStack(alignment: .leading, spacing: Spacing.xs) {
                KitchenTextField(
                    label: item.wrappedValue.priceLabel,
                    text: item.unitPriceText,
                    keyboard: .decimalPad
                )

                if let suggested = item.wrappedValue.currentSuggestedPriceCents {
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

    let onSelect: (RemoteRecipeListItem) -> Void

    @State private var model: RecipePickerModel

    init(model: RecipePickerModel = RecipePickerModel(), onSelect: @escaping (RemoteRecipeListItem) -> Void) {
        _model = State(initialValue: model)
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            content
                .background(.canvasBackground)
                .navigationTitle("Productos")
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

    private func select(_ item: RemoteRecipeListItem) {
        model.selectingId = item.id
        onSelect(item)
        dismiss()
    }
}

#if DEBUG
private func makeMockOrderFormModel() -> OrderFormModel {
    OrderFormModel(
        draftItems: [
            DraftOrderItem(
                recipeId: "rec-1",
                recipeName: "Galletas con chispas",
                soldBy: .unit,
                yieldQuantity: 12,
                yieldUnit: .pz,
                quantityText: "4",
                unitPriceText: "13",
                suggestedPriceBatchCents: 15600,
                suggestedPriceUnitCents: 1300
            ),
            DraftOrderItem(
                recipeId: "rec-2",
                recipeName: "Pastel de zanahoria",
                soldBy: .batch,
                yieldQuantity: 12,
                yieldUnit: .pz,
                quantityText: "1",
                unitPriceText: "156",
                suggestedPriceBatchCents: 15600,
                suggestedPriceUnitCents: 1300
            )
        ]
    )
}

#Preview("Formulario con pieza y tanda — Normal") {
    OrderFormView(model: makeMockOrderFormModel()) { _ in }
}

#Preview("Formulario con pieza y tanda — AX3") {
    OrderFormView(model: makeMockOrderFormModel()) { _ in }
        .dynamicTypeSize(.accessibility3)
}

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

#Preview("Editar pedido con cliente — Claro") {
    var order = RemoteOrder.mockPendingToday
    order.customerId = "c-1"
    return OrderFormView(order: order) { _ in }
}

#Preview("Selector de receta") {
    RecipePickerSheet(
        model: RecipePickerModel(recipes: [.mockChocolate, .mockVainilla, .mockIncomplete])
    ) { _ in }
}
#endif
