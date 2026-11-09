import SwiftUI
import KitchenDomain

/// Hoja para configurar o quitar el precio de venta propio de una receta (Bloque I31).
struct SalePriceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let recipe: Recipe
    let cost: RecipeCost
    let store: LocalStore

    @State private var priceText: String
    @State private var soldBy: OrderSoldBy
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        recipe: Recipe,
        cost: RecipeCost,
        store: LocalStore = .shared
    ) {
        self.recipe = recipe
        self.cost = cost
        self.store = store

        _soldBy = State(initialValue: recipe.salePriceSoldBy ?? .batch)
        if let currentCents = recipe.salePriceCents {
            _priceText = State(initialValue: CurrencyMath.formatForInput(cents: currentCents))
        } else {
            _priceText = State(initialValue: "")
        }
    }

    private var yieldsMultiple: Bool {
        let yield = Qty.decimal(recipe.yieldQuantity) ?? 1
        return yield > 1
    }

    private var unitOptionTitle: String {
        switch recipe.yieldUnit {
        case .pz:
            return "Por pieza"
        case .g:
            return "Por g"
        case .ml:
            return "Por ml"
        }
    }

    private var parsedCents: Int? {
        RecordPriceModel.parsePriceCents(priceText)
    }

    private var canSave: Bool {
        guard let cents = parsedCents, cents > 0 else { return false }
        return !isSaving
    }

    private var liveProfit: Profit? {
        guard let cents = parsedCents else { return nil }
        let costCents: Int
        switch soldBy {
        case .batch:
            costCents = cost.batchCostCents
        case .unit:
            costCents = CostingMath.roundToCents(Qty.decimal(cost.costPerYieldUnit) ?? Decimal(0))
        }
        return Profit.make(priceCents: cents, costCents: costCents)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    if yieldsMultiple {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Picker("Modo de venta", selection: $soldBy) {
                                Text("Por tanda").tag(OrderSoldBy.batch)
                                Text(unitOptionTitle).tag(OrderSoldBy.unit)
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        KitchenTextField(
                            label: soldBy == .batch ? "Precio por tanda" : "Precio \(unitOptionTitle.lowercased())",
                            text: $priceText,
                            keyboard: .decimalPad
                        )

                        if let profit = liveProfit {
                            if profit.profitCents < 0 {
                                Text("Pierdes \(Money.format(cents: abs(profit.profitCents)))")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.warningText)
                                    .monospacedDigit()
                            } else if let pct = profit.percent {
                                Text("Ganas \(Money.format(cents: profit.profitCents)) (\(pct) %)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.tint)
                                    .monospacedDigit()
                            } else {
                                Text("Ganas \(Money.format(cents: profit.profitCents))")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.tint)
                                    .monospacedDigit()
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.warningText)
                        }
                    }

                    if recipe.salePriceCents != nil {
                        Button(role: .destructive) {
                            removeCustomPrice()
                        } label: {
                            Text("Quitar mi precio")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.warningText)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, Spacing.sm)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving)
                    }
                }
                .padding(Spacing.xl)
            }
            .background(.canvasBackground)
            .navigationTitle("Tu precio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        savePrice()
                    }
                    .fontWeight(.bold)
                    .disabled(!canSave)
                }
            }
        }
    }

    private func savePrice() {
        guard let cents = parsedCents, cents > 0 else { return }
        isSaving = true
        errorMessage = nil

        let modeToSave: OrderSoldBy = yieldsMultiple ? soldBy : .batch

        do {
            try store.mutate { data, ctx in
                try data.updateRecipe(
                    id: recipe.id,
                    salePriceCents: .some(cents),
                    salePriceSoldBy: .some(modeToSave),
                    ctx: ctx
                )
            }
            dismiss()
        } catch let domainError as DomainError {
            errorMessage = domainError.detail
            isSaving = false
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }

    private func removeCustomPrice() {
        isSaving = true
        errorMessage = nil

        do {
            try store.mutate { data, ctx in
                try data.updateRecipe(
                    id: recipe.id,
                    salePriceCents: .some(nil),
                    salePriceSoldBy: .some(nil),
                    ctx: ctx
                )
            }
            dismiss()
        } catch let domainError as DomainError {
            errorMessage = domainError.detail
            isSaving = false
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }
}

// MARK: - Previews

#if DEBUG
private func makeSheetPreviewStore() -> (Recipe, RecipeCost, LocalStore) {
    let store = LocalStore.preview()
    let recipe = store.data.recipe(id: "rec-galletas")!
    let cost = try! store.data.costingIndex().calculateRecipeCost(recipe: recipe, version: nil, now: Date())
    return (recipe, cost, store)
}

#Preview("Tu precio — nuevo") {
    let (recipe, cost, store) = makeSheetPreviewStore()
    SalePriceSheet(recipe: recipe, cost: cost, store: store)
}

#Preview("Tu precio — con precio") {
    let (baseRecipe, cost, store) = makeSheetPreviewStore()
    var recipeWithPrice = baseRecipe
    recipeWithPrice.salePriceCents = 1800
    recipeWithPrice.salePriceSoldBy = .unit
    return SalePriceSheet(recipe: recipeWithPrice, cost: cost, store: store)
}

#Preview("Tu precio AX3") {
    let (recipe, cost, store) = makeSheetPreviewStore()
    SalePriceSheet(recipe: recipe, cost: cost, store: store)
        .dynamicTypeSize(.accessibility3)
}
#endif
