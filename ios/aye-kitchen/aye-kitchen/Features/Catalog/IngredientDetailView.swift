import SwiftUI
import KitchenDomain

/// Detalle del ingrediente (especificación B1 / I1 / I16).
struct IngredientDetailView: View {
    let ingredientId: String
    private let store: LocalStore

    @State private var showingEditSheet = false

    init(ingredientId: String, store: LocalStore = .shared) {
        self.ingredientId = ingredientId
        self.store = store
    }

    private var ingredient: Ingredient? {
        store.data.ingredients.first(where: { $0.id == ingredientId && $0.isActive })
    }

    var body: some View {
        Group {
            if let ingredient {
                List {
                    Section {
                        IngredientBrandsSection(ingredientId: ingredient.id, store: store)
                    } header: {
                        Text("Marcas y precios")
                    } footer: {
                        Text("Tus recetas usan la marca que dice La que usamos. Puedes elegir otra en cada receta.")
                    }

                    Section("Cómo lo mides") {
                        Text(ingredient.buyingUnitDescription)
                            .font(.body)
                            .foregroundStyle(.inkPrimary)
                    }

                    Section("Equivalencias") {
                        if ingredient.conversions.isEmpty {
                            Text("Aún no tiene. Te las preguntamos cuando las necesites.")
                                .font(.body)
                                .foregroundStyle(.inkMuted)
                        } else {
                            ForEach(ingredient.conversions, id: \.unitId) { conversion in
                                let unitName = store.data.costingIndex().unitsById[conversion.unitId]?.name ?? conversion.unitId
                                Text("1 \(unitName) = \(Quantity.format(conversion.quantityInBase)) \(ingredient.baseUnit.rawValue)")
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

                    Section("Fotos") {
                        ReferencesSection(owner: .ingredient(ingredient.id), showsTitle: false, store: store)
                    }
                }
                .navigationTitle(ingredient.name)
            } else {
                ContentUnavailableView("Ingrediente no encontrado", systemImage: "questionmark.folder")
                    .navigationTitle("Ingrediente")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(.canvasBackground)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if ingredient != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Editar") {
                        showingEditSheet = true
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            IngredientFormView(mode: .edit(ingredientId: ingredientId), store: store)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Claro") {
    NavigationStack {
        IngredientDetailView(ingredientId: "ing-harina", store: .preview())
    }
}

#Preview("Letra AX3") {
    NavigationStack {
        IngredientDetailView(ingredientId: "ing-harina", store: .preview())
    }
    .dynamicTypeSize(.accessibility3)
}
#endif
