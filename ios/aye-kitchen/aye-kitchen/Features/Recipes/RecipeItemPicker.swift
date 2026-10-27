import SwiftUI

/// Hoja para seleccionar un ingrediente o una subreceta para la receta.
struct RecipeItemPicker: View {
    @Environment(\.dismiss) private var dismiss

    @State private var model: RecipeItemPickerModel
    @State private var selectedTarget: LineTarget?

    let allUnits: [MeasureUnit]
    let onSelectLine: @MainActor @Sendable (RecipeEditorLine) -> Void

    init(
        editingRecipeId: String? = nil,
        allUnits: [MeasureUnit],
        mockIngredients: [Ingredient]? = nil,
        mockSubrecipes: [UsableSubrecipe]? = nil,
        mockAllRecipes: [RecipeListItem]? = nil,
        onSelectLine: @escaping @MainActor @Sendable (RecipeEditorLine) -> Void
    ) {
        _model = State(initialValue: RecipeItemPickerModel(
            editingRecipeId: editingRecipeId,
            mockIngredients: mockIngredients,
            mockSubrecipes: mockSubrecipes,
            mockAllRecipes: mockAllRecipes
        ))
        self.allUnits = allUnits
        self.onSelectLine = onSelectLine
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.md) {
                Picker("Categoría", selection: $model.tab) {
                    ForEach(RecipeItemPickerTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.sm)

                contentList
            }
            .background(.canvasBackground)
            .navigationTitle("Agregar a la receta")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: Binding(
                    get: { model.searchText },
                    set: { model.onSearchTextChanged($0) }
                ),
                prompt: "Buscar en el catálogo…"
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
                }
            }
            .sheet(item: $selectedTarget) { target in
                RecipeLineSheet(target: target, allUnits: allUnits) { line in
                    onSelectLine(line)
                    dismiss()
                }
            }
            .task {
                await model.loadInitialData()
            }
        }
    }

    @ViewBuilder
    private var contentList: some View {
        if model.isLoading && model.ingredients.isEmpty && model.usableSubrecipes.isEmpty && model.allRecipes.isEmpty {
            ProgressView()
                .tint(Color.accentColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                switch model.tab {
                case .ingredients:
                    if model.ingredients.isEmpty {
                        emptyState(text: "No se encontraron ingredientes.")
                    } else {
                        ForEach(model.ingredients) { ingredient in
                            Button {
                                selectedTarget = .ingredient(ingredient)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ingredient.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.inkPrimary)

                                    Text(RecipeItemPickerModel.ingredientSubtitle(for: ingredient.baseUnit))
                                        .font(.subheadline)
                                        .foregroundStyle(.inkMuted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.surfaceCard)
                        }
                    }
                case .myRecipes:
                    if model.editingRecipeId != nil {
                        if model.filteredSubrecipes.isEmpty {
                            emptyState(text: "No hay subrecetas disponibles.")
                        } else {
                            ForEach(model.filteredSubrecipes) { subrecipe in
                                Button {
                                    selectedTarget = .subrecipe(
                                        id: subrecipe.id,
                                        name: subrecipe.name,
                                        yieldUnit: subrecipe.yieldUnit
                                    )
                                } label: {
                                    HStack(spacing: Spacing.sm) {
                                        Image(systemName: "birthday.cake")
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(.accentTextDeep)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(subrecipe.name)
                                                .font(.body.weight(.semibold))
                                                .foregroundStyle(.inkPrimary)

                                            Text(RecipeItemPickerModel.recipeSubtitle(for: subrecipe.yieldUnit))
                                                .font(.subheadline)
                                                .foregroundStyle(.inkMuted)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.surfaceCard)
                            }
                        }
                    } else {
                        if model.filteredAllRecipes.isEmpty {
                            emptyState(text: "No hay recetas disponibles.")
                        } else {
                            ForEach(model.filteredAllRecipes) { item in
                                Button {
                                    selectedTarget = .subrecipe(
                                        id: item.recipe.id,
                                        name: item.recipe.name,
                                        yieldUnit: item.recipe.yieldUnit
                                    )
                                } label: {
                                    HStack(spacing: Spacing.sm) {
                                        Image(systemName: "birthday.cake")
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(.accentTextDeep)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.recipe.name)
                                                .font(.body.weight(.semibold))
                                                .foregroundStyle(.inkPrimary)

                                            Text(RecipeItemPickerModel.recipeSubtitle(for: item.recipe.yieldUnit))
                                                .font(.subheadline)
                                                .foregroundStyle(.inkMuted)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.surfaceCard)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    private func emptyState(text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.inkMuted)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, Spacing.xl)
            .listRowBackground(Color.clear)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Selector de ingredientes y recetas") {
    let mockIngredients = [
        Ingredient(
            id: "ing-1",
            name: "Harina de trigo",
            baseUnit: .g,
            group: "Secos",
            notes: nil,
            conversions: [],
            createdAt: .now,
            updatedAt: .now
        ),
        Ingredient(
            id: "ing-2",
            name: "Leche entera",
            baseUnit: .ml,
            group: "Lácteos",
            notes: nil,
            conversions: [],
            createdAt: .now,
            updatedAt: .now
        ),
        Ingredient(
            id: "ing-3",
            name: "Huevo",
            baseUnit: .pz,
            group: "Frescos",
            notes: nil,
            conversions: [],
            createdAt: .now,
            updatedAt: .now
        )
    ]
    let mockSubrecipes = [
        UsableSubrecipe(id: "rec-1", name: "Betún de mantequilla", yieldUnit: .g)
    ]

    RecipeItemPicker(
        allUnits: [],
        mockIngredients: mockIngredients,
        mockSubrecipes: mockSubrecipes
    ) { _ in }
}

#Preview("Selector - Accesibilidad AX3") {
    let mockIngredients = [
        Ingredient(
            id: "ing-1",
            name: "Harina de trigo",
            baseUnit: .g,
            group: "Secos",
            notes: nil,
            conversions: [],
            createdAt: .now,
            updatedAt: .now
        )
    ]

    RecipeItemPicker(
        allUnits: [],
        mockIngredients: mockIngredients
    ) { _ in }
    .dynamicTypeSize(.accessibility3)
}
#endif
