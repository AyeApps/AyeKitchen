import SwiftUI
import KitchenDomain

/// Tablero de costos de recetas (Bloque I22 local-first).
struct RecipeCostDashboardView: View {
    @Bindable var model: FinanceModel
    let store: LocalStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                headerStatsView

                if model.recipeDashboard.items.isEmpty {
                    emptyView
                } else {
                    recipesList
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxl)
        }
    }

    // MARK: - Encabezado y Estadísticas

    private var headerStatsView: some View {
        let totals = model.recipeDashboard.totals

        return VStack(alignment: .leading, spacing: Spacing.md) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    summaryBadges(totals: totals)
                }
            } else {
                HStack(spacing: Spacing.sm) {
                    summaryBadges(totals: totals)
                }
            }

            HStack {
                Text("Ordenar por")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.inkMuted)

                Spacer()

                Menu {
                    ForEach(CostDashboardSortOrder.allCases, id: \.self) { sort in
                        Button {
                            model.setSortOrder(sort)
                        } label: {
                            if model.recipeDashboardSort == sort {
                                Label(sort.label, systemImage: "checkmark")
                            } else {
                                Text(sort.label)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Text(model.recipeDashboardSort.label)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.tint)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tint)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.accentSoft, in: .capsule)
                }
                .accessibilityLabel("Orden actual: \(model.recipeDashboardSort.label)")
            }
        }
    }

    @ViewBuilder
    private func summaryBadges(totals: CostDashboardTotals) -> some View {
        let recipeLabel = totals.totalRecipes == 1 ? "1 receta" : "\(totals.totalRecipes) recetas"
        Text(recipeLabel)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.inkMuted)

        if totals.incompleteRecipes > 0 {
            Button {
                model.setSortOrder(.needsReview)
            } label: {
                Chip("\(totals.incompleteRecipes) con precios faltantes", tone: .warning)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(totals.incompleteRecipes) recetas con precios faltantes. Toca para ordenar por revisar.")
        }

        if totals.stalePriceRecipes > 0 {
            Button {
                model.setSortOrder(.needsReview)
            } label: {
                Chip("\(totals.stalePriceRecipes) con precios viejos", tone: .warning)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(totals.stalePriceRecipes) recetas con precios viejos. Toca para ordenar por revisar.")
        }
    }

    // MARK: - Lista de Recetas

    private var recipesList: some View {
        RowGroup {
            ForEach(model.recipeDashboard.items) { item in
                NavigationLink {
                    RecipeDetailView(recipeId: item.id, store: store)
                } label: {
                    RecipeCostRow(item: item)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "book.closed")
                .font(.system(size: 36))
                .foregroundStyle(.inkMuted)

            Text("Todavía no tienes recetas")
                .font(.headline)
                .foregroundStyle(.inkPrimary)

            Text("Arma una receta en la pestaña Recetas para ver su costo y ganancia aquí.")
                .font(.subheadline)
                .foregroundStyle(.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xxl)
    }
}

// MARK: - Fila de Receta en el Tablero

struct RecipeCostRow: View {
    let item: CostDashboardItem
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                standardLayout
            }
        }
        .padding(.vertical, Spacing.md)
        .padding(.horizontal, Spacing.lg)
        .contentShape(Rectangle())
    }

    private var standardLayout: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.name)
                    .font(.headline)
                    .foregroundStyle(.inkPrimary)

                Spacer()

                chipsView
            }

            HStack(spacing: Spacing.md) {
                batchCostView

                if let profit = item.suggestedProfitCents, item.complete {
                    Text("·")
                        .foregroundStyle(.inkMuted)

                    Text("Ganancia: \(Money.format(cents: profit)) por tanda")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.tint)
                }
            }

            HStack {
                if let unitCost = unitCostDetail {
                    Text(unitCost)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.inkMuted)
                }

                Spacer()

                Text("\(item.effectiveMarginPercent) % margen")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.inkSecondary)
            }
        }
    }

    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(item.name)
                .font(.headline)
                .foregroundStyle(.inkPrimary)

            chipsView

            batchCostView

            if let profit = item.suggestedProfitCents, item.complete {
                Text("Ganancia: \(Money.format(cents: profit)) por tanda")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.tint)
            }

            if let unitCost = unitCostDetail {
                Text(unitCost)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.inkMuted)
            }

            Text("\(item.effectiveMarginPercent) % margen")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.inkSecondary)
        }
    }

    @ViewBuilder
    private var chipsView: some View {
        if !item.complete {
            Chip("Falta precio", tone: .warning)
        } else if item.hasStalePrices {
            Chip("Precio viejo", tone: .warning)
        }
    }

    @ViewBuilder
    private var batchCostView: some View {
        if let batchCost = item.batchCostCents {
            Text("Tanda: \(Money.format(cents: batchCost))")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.inkPrimary)
        } else {
            Text("Tanda: sin calcular")
                .font(.subheadline)
                .foregroundStyle(.inkMuted)
        }
    }

    private var unitCostDetail: String? {
        if item.yieldUnit == .pz {
            guard let cost = item.costPerYieldUnitCents else { return nil }
            let costStr = Money.format(cents: cost)
            if let suggested = item.suggestedPricePerYieldUnitCents {
                return "Por pieza: \(costStr) · sugerido \(Money.format(cents: suggested))"
            }
            return "Por pieza: \(costStr)"
        }

        if let servings = item.servings, servings > 0, let cost = item.costPerServingCents {
            let costStr = Money.format(cents: cost)
            if let batchPrice = item.suggestedPriceCents {
                let servSug = CostingMath.roundToCents(Decimal(batchPrice) / Decimal(servings))
                return "Por porción: \(costStr) · sugerido \(Money.format(cents: servSug))"
            }
            return "Por porción: \(costStr)"
        }

        if let cost = item.costPerYieldUnitCents {
            let costStr = Money.format(cents: cost)
            if let suggested = item.suggestedPricePerYieldUnitCents {
                return "Por \(item.yieldUnit.rawValue): \(costStr) · sugerido \(Money.format(cents: suggested))"
            }
            return "Por \(item.yieldUnit.rawValue): \(costStr)"
        }

        return nil
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Tablero de costos") {
    let store = LocalStore.preview()
    let model = FinanceModel(store: store)
    return NavigationStack {
        RecipeCostDashboardView(model: model, store: store)
    }
}

#Preview("Tablero de costos — AX3") {
    let store = LocalStore.preview()
    let model = FinanceModel(store: store)
    return NavigationStack {
        RecipeCostDashboardView(model: model, store: store)
    }
    .dynamicTypeSize(.accessibility3)
}
#endif
