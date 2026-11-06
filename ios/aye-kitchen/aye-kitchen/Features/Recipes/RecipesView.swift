import SwiftUI
import KitchenDomain

/// Lista de recetas según Bloque I3 / I13 / I17 local-first.
struct RecipesView: View {
    @State private var model: RecipesModel
    private let store: LocalStore
    @State private var showingNewRecipe = false
    @State private var recipeToDelete: RecipeListItem?
    @State private var deleteErrorMessage: String?

    init(store: LocalStore = .shared) {
        self.store = store
        self._model = State(initialValue: RecipesModel(store: store))
    }

    var body: some View {
        NavigationStack {
            content
                .background(.canvasBackground)
                .navigationTitle("Recetas")
                .searchable(text: $model.query, prompt: "Buscar receta")
                .onChange(of: model.query) { _, _ in
                    model.recalculate()
                }
                .task(id: store.revision) {
                    model.recalculateIfNeeded()
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        AddToolbarButton(label: "Nueva receta") {
                            showingNewRecipe = true
                        }
                    }
                }
                .sheet(isPresented: $showingNewRecipe) {
                    RecipeEditorView(mode: .create, store: store)
                }
                .navigationDestination(for: String.self) { recipeId in
                    RecipeDetailView(recipeId: recipeId, store: store)
                }
                .confirmationDialog(
                    "¿Borrar esta receta?",
                    isPresented: Binding(
                        get: { recipeToDelete != nil },
                        set: { if !$0 { recipeToDelete = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Borrar receta", role: .destructive) {
                        if let recipe = recipeToDelete {
                            do {
                                try model.deleteRecipe(id: recipe.id)
                                recipeToDelete = nil
                            } catch let domainError as DomainError {
                                if case .inUse = domainError {
                                    deleteErrorMessage = "No se puede borrar: otra receta la usa como parte de ella."
                                } else {
                                    deleteErrorMessage = domainError.localizedDescription
                                }
                                recipeToDelete = nil
                            } catch {
                                deleteErrorMessage = error.localizedDescription
                                recipeToDelete = nil
                            }
                        }
                    }
                    Button("Cancelar", role: .cancel) {
                        recipeToDelete = nil
                    }
                } message: {
                    if let recipe = recipeToDelete {
                        Text("Se eliminará la receta '\(recipe.name)'. Esta acción no se puede deshacer.")
                    }
                }
                .alert("No se pudo borrar", isPresented: Binding(
                    get: { deleteErrorMessage != nil },
                    set: { if !$0 { deleteErrorMessage = nil } }
                )) {
                    Button("Entendido", role: .cancel) {}
                } message: {
                    if let deleteErrorMessage {
                        Text(deleteErrorMessage)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isEmpty {
            ScrollView {
                if model.isSearching {
                    ContentUnavailableView.search(text: model.query)
                        .padding(.top, 40)
                } else {
                    ContentUnavailableView {
                        Label("Todavía no hay recetas", systemImage: "book.closed")
                    } description: {
                        Text("Arma una receta y te decimos cuánto te cuesta.")
                    } actions: {
                        Button {
                            showingNewRecipe = true
                        } label: {
                            Text("Nueva receta")
                        }
                        .buttonStyle(.kitchenPrimary)
                        .padding(.horizontal, Spacing.xxl)
                    }
                    .padding(.top, 40)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(model.items) { item in
                    NavigationLink(value: item.id) {
                        RecipeRow(item: item)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            recipeToDelete = item
                        } label: {
                            Label("Borrar", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }
}

/// Fila individual de receta en la lista.
struct RecipeRow: View {
    let item: RecipeListItem

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(item.name)
                    .font(.headline)
                    .foregroundStyle(.inkPrimary)

                if let cost = item.batchCostCents {
                    Text("Te cuesta \(Money.format(cents: cost))")
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)
                        .monospacedDigit()
                } else {
                    Text("No pudimos calcular el costo")
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)
                }
            }

            Spacer()

            if !item.complete {
                Chip("Falta precio", tone: .warning)
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}

#if DEBUG
#Preview("Claro") {
    RecipesView(store: .preview())
}

#Preview("Letra AX3") {
    RecipesView(store: .preview())
        .dynamicTypeSize(.accessibility3)
}
#endif
