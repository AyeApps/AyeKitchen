import Foundation
import SwiftUI
import KitchenDomain

/// Modelo de presentación para el selector de recetas en pedidos (MVVM, Regla 5 / Bloque I18 local-first).
@Observable
final class RecipePickerModel {
    var query: String = ""
    var store: LocalStore

    init(store: LocalStore = .shared) {
        self.store = store
    }

    var recipes: [RecipeListItem] {
        store.data.listRecipes(query: query)
    }
}

/// Hoja para buscar y seleccionar una receta para una línea de pedido (Bloque I18 local-first).
struct RecipePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSelect: (RecipeListItem) -> Void

    @State private var model: RecipePickerModel

    init(
        store: LocalStore = .shared,
        onSelect: @escaping (RecipeListItem) -> Void
    ) {
        self._model = State(initialValue: RecipePickerModel(store: store))
        self.onSelect = onSelect
    }

    init(
        model: RecipePickerModel,
        onSelect: @escaping (RecipeListItem) -> Void
    ) {
        self._model = State(initialValue: model)
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            content
                .background(.canvasBackground)
                .navigationTitle("Productos")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $model.query, prompt: "Buscar receta")
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
        let items = model.recipes
        if items.isEmpty {
            if !model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    "No hay recetas",
                    systemImage: "magnifyingglass",
                    description: Text("No se encontraron recetas con ese nombre.")
                )
            } else {
                ContentUnavailableView(
                    "Todavía no hay recetas",
                    systemImage: "book.closed",
                    description: Text("Crea una receta en la pestaña Recetas.")
                )
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    RowGroup {
                        ForEach(items) { item in
                            Button {
                                select(item)
                            } label: {
                                HStack(spacing: Spacing.md) {
                                    VStack(alignment: .leading, spacing: Spacing.xs) {
                                        Text(item.name)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(.inkPrimary)
                                    }

                                    Spacer()

                                    if !item.complete {
                                        Chip("Falta precio", tone: .warning)
                                    }

                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.inkMuted)
                                }
                                .padding(Spacing.lg)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(Spacing.xl)
            }
        }
    }

    private func select(_ item: RecipeListItem) {
        onSelect(item)
        dismiss()
    }
}

#if DEBUG
#Preview("Selector de recetas") {
    RecipePickerSheet(store: .preview()) { _ in }
}

#Preview("Selector de recetas — AX3") {
    RecipePickerSheet(store: .preview()) { _ in }
        .dynamicTypeSize(.accessibility3)
}
#endif
