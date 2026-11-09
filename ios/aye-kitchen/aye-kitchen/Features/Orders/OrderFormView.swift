import SwiftUI
import TipKit
import KitchenDomain

/// Formulario para crear o editar un pedido (Bloque I18 local-first).
struct OrderFormView: View {
    typealias Mode = OrderFormModel.Mode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var model: OrderFormModel
    @State private var showingRecipePicker = false
    @State private var showingCustomerPicker = false
    let onSave: (@MainActor @Sendable (Order) -> Void)?

    init(
        _ mode: Mode = .create,
        store: LocalStore = .shared,
        onSave: (@MainActor @Sendable (Order) -> Void)? = nil
    ) {
        self._model = State(initialValue: OrderFormModel(mode: mode, store: store))
        self.onSave = onSave
    }

    init(
        mode: Mode,
        store: LocalStore = .shared,
        onSave: (@MainActor @Sendable (Order) -> Void)? = nil
    ) {
        self.init(mode, store: store, onSave: onSave)
    }

    init(
        orderId: String?,
        store: LocalStore = .shared,
        onSave: (@MainActor @Sendable (Order) -> Void)? = nil
    ) {
        let mode: Mode = orderId.map { .edit(orderId: $0) } ?? .create
        self.init(mode, store: store, onSave: onSave)
    }

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
                        saveOrder()
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
                RecipePickerSheet(store: model.store) { selectedRecipe in
                    model.addRecipe(selectedRecipe)
                }
            }
            .sheet(isPresented: $showingCustomerPicker) {
                CustomerPickerSheet(store: model.store) { selectedCustomer in
                    model.selectCustomer(selectedCustomer)
                }
            }
            .onAppear {
                OrderSoldByTip.hasRecipeYieldingSeveral = model.hasRecipeYieldingSeveral
            }
            .onChange(of: model.hasRecipeYieldingSeveral) { _, newValue in
                OrderSoldByTip.hasRecipeYieldingSeveral = newValue
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
                if item.wrappedValue.id == model.firstYieldingSeveralItemId {
                    TipView(OrderSoldByTip())
                        .tipBackground(.surfaceCard)
                }

                Picker("Modo de venta", selection: Binding(
                    get: { item.wrappedValue.soldBy },
                    set: { item.wrappedValue.changeMode(to: $0) }
                )) {
                    Text(item.wrappedValue.unitOptionTitle).tag(OrderSoldBy.unit)
                    Text("Por tanda").tag(OrderSoldBy.batch)
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

                if let helper = item.wrappedValue.priceHelperText {
                    Text(helper)
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

    private func saveOrder() {
        do {
            let saved = try model.save()
            onSave?(saved)
            dismiss()
        } catch {
            // El error ya se procesa y muestra en model.errorMessage
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Nuevo pedido") {
    OrderFormView(.create, store: .preview())
}

#Preview("Editar pedido — ord-2") {
    OrderFormView(.edit(orderId: "ord-2"), store: .preview())
}

#Preview("Letra AX3") {
    OrderFormView(.create, store: .preview())
        .dynamicTypeSize(.accessibility3)
}
#endif
