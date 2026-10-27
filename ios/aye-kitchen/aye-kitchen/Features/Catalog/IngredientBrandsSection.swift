import SwiftUI

/// Sección de marcas y precios en el detalle del ingrediente.
/// En este bloque (I1) solo muestra el estado provisional. El siguiente bloque (I2) reemplazará este archivo.
struct IngredientBrandsSection: View {
    let ingredient: Ingredient

    init(ingredient: Ingredient) {
        self.ingredient = ingredient
    }

    var body: some View {
        Text("Pronto podrás agregar marcas y precios aquí.")
            .font(.body)
            .foregroundStyle(.inkMuted)
    }
}

#if DEBUG
#Preview("Claro") {
    IngredientBrandsSection(
        ingredient: Ingredient(
            id: "ing_preview",
            name: "Harina de trigo",
            baseUnit: .g,
            group: "Harinas",
            notes: nil,
            conversions: [],
            createdAt: Date(),
            updatedAt: Date()
        )
    )
}

#Preview("Letra AX3") {
    IngredientBrandsSection(
        ingredient: Ingredient(
            id: "ing_preview",
            name: "Harina de trigo",
            baseUnit: .g,
            group: "Harinas",
            notes: nil,
            conversions: [],
            createdAt: Date(),
            updatedAt: Date()
        )
    )
    .dynamicTypeSize(.accessibility3)
}
#endif
