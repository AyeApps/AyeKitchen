import SwiftUI
import TipKit
import KitchenDomain

/// Hoja para seleccionar un ingrediente o una subreceta para la receta (Bloque I3b / I17 local-first).
struct RecipeItemPicker: View {
    @Environment(\.dismiss) private var dismiss

    @State private var model: RecipeItemPickerModel
    private let store: LocalStore
    @State private var selectedTarget: LineTarget?
    @State private var showingNewIngredientSheet = false
    @State private var pendingTargetIngredient: Ingredient?

    let allUnits: [KitchenUnit]
    let onSelectLine: @MainActor @Sendable (RecipeEditorLine) -> Void

    init(
        editingRecipeId: String? = nil,
        allUnits: [KitchenUnit],
        store: LocalStore = .shared,
        onSelectLine: @escaping @MainActor @Sendable (RecipeEditorLine) -> Void
    ) {
        self.store = store
        _model = State(initialValue: RecipeItemPickerModel(
            editingRecipeId: editingRecipeId,
            store: store
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
                text: $model.searchText,
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
                RecipeLineSheet(target: target, allUnits: allUnits, store: store) { line in
                    onSelectLine(line)
                    dismiss()
                }
            }
            .sheet(isPresented: $showingNewIngredientSheet, onDismiss: {
                if let pending = pendingTargetIngredient {
                    pendingTargetIngredient = nil
                    selectedTarget = .ingredient(pending)
                }
            }) {
                IngredientFormView(
                    mode: .create,
                    initialName: model.searchText.trimmingCharacters(in: .whitespaces),
                    store: store
                ) { newIngredient in
                    pendingTargetIngredient = newIngredient
                }
            }
        }
    }

    @ViewBuilder
    private var contentList: some View {
        List {
            switch model.tab {
            case .ingredients:
                Button {
                    showingNewIngredientSheet = true
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "plus.circle.fill")
                            .imageScale(.medium)
                        Text(newIngredientButtonTitle)
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                }
                .listRowBackground(Color.surfaceCard)

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
                if model.usableSubrecipes.isEmpty {
                    emptyState(text: "No hay subrecetas disponibles.")
                } else {
                    TipView(RecipeSubrecipeTip())
                        .tipBackground(.surfaceCard)

                    ForEach(model.usableSubrecipes) { subrecipe in
                        Button {
                            selectedTarget = .subrecipe(
                                id: subrecipe.id,
                                name: subrecipe.name,
                                yieldUnit: subrecipe.yieldUnit
                            )
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "fork.knife")
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
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.surfaceCard)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var newIngredientButtonTitle: String {
        let trimmed = model.searchText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return "Nuevo ingrediente"
        } else {
            return "Crear \"\(trimmed)\""
        }
    }

    private func emptyState(text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.inkMuted)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, Spacing.xl)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Selector de ingredientes") {
    let previewStore = LocalStore.preview()
    RecipeItemPicker(
        allUnits: previewStore.data.availableKitchenUnits(),
        store: previewStore
    ) { _ in }
}

#Preview("Selector de ingredientes — Letra AX3") {
    let previewStore = LocalStore.preview()
    RecipeItemPicker(
        allUnits: previewStore.data.availableKitchenUnits(),
        store: previewStore
    ) { _ in }
    .dynamicTypeSize(.accessibility3)
}
#endif
