import SwiftUI

/// Detalle del ingrediente (especificación B1 / I1).
struct IngredientDetailView: View {
    @State private var ingredient: Ingredient
    var onUpdate: ((Ingredient) -> Void)?
    var onDelete: ((String) -> Void)?

    @State private var showingEditSheet = false

    init(
        ingredient: Ingredient,
        onUpdate: ((Ingredient) -> Void)? = nil,
        onDelete: ((String) -> Void)? = nil
    ) {
        self._ingredient = State(initialValue: ingredient)
        self.onUpdate = onUpdate
        self.onDelete = onDelete
    }

    var body: some View {
        List {
            Section("Cómo lo compras") {
                Text(ingredient.buyingUnitDescription)
                    .font(.body)
                    .foregroundStyle(.inkPrimary)
            }

            Section("Marcas y precios") {
                IngredientBrandsSection(ingredient: ingredient)
            }

            Section("Equivalencias") {
                if ingredient.conversions.isEmpty {
                    Text("Aún no tiene. Te las preguntamos cuando las necesites.")
                        .font(.body)
                        .foregroundStyle(.inkMuted)
                } else {
                    ForEach(ingredient.conversions, id: \.unitId) { conversion in
                        Text("1 \(conversion.unitName) = \(Quantity.format(conversion.quantityInBase)) \(ingredient.baseUnit.rawValue)")
                            .font(.body)
                            .foregroundStyle(.inkPrimary)
                    }
                }
            }

            if let notes = ingredient.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("Notas") {
                    Text(notes)
                        .font(.body)
                        .foregroundStyle(.inkPrimary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(.canvasBackground)
        .navigationTitle(ingredient.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Editar") {
                    showingEditSheet = true
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            IngredientFormView(mode: .edit(ingredient)) { updated in
                self.ingredient = updated
                onUpdate?(updated)
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
private let detailPreviewIngredient = Ingredient(
    id: "ing_preview_detail",
    name: "Harina de trigo",
    baseUnit: .g,
    group: "Harinas",
    notes: "Comprar en bulto de 25 kg para mejor precio en la central de abastos.",
    conversions: [
        IngredientConversion(unitId: "u_tz", unitName: "taza", quantityInBase: "125")
    ],
    createdAt: Date(),
    updatedAt: Date()
)

#Preview("Claro") {
    NavigationStack {
        IngredientDetailView(ingredient: detailPreviewIngredient)
    }
}

#Preview("Letra AX3") {
    NavigationStack {
        IngredientDetailView(ingredient: detailPreviewIngredient)
    }
    .dynamicTypeSize(.accessibility3)
}
#endif
