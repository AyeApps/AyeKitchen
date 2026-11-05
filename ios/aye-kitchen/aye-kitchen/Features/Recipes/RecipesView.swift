import SwiftUI

/// Lista de recetas según Bloque I3 / I13.
struct RecipesView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var model = RecipesModel()
    @State private var showingNewRecipe = false
    @State private var recipeToDelete: RecipeListItem?
    @State private var deleteErrorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var isVisible = false

    var body: some View {
        NavigationStack {
            content
                .background(.canvasBackground)
                .navigationTitle("Recetas")
                .searchable(text: $model.query, prompt: "Buscar receta")
                .onChange(of: model.query) { _, newQuery in
                    handleSearch(query: newQuery)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        AddToolbarButton(label: "Nueva receta") {
                            showingNewRecipe = true
                        }
                    }
                }
                .sheet(isPresented: $showingNewRecipe) {
                    RecipeEditorView { _ in
                        Task {
                            await model.refresh()
                        }
                    }
                }
                .navigationDestination(for: String.self) { recipeId in
                    RecipeDetailView(recipeId: recipeId)
                }
                .task {
                    await model.load()
                }
                .onAppear {
                    isVisible = true
                }
                .onDisappear {
                    isVisible = false
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active, isVisible else { return }
                    Task {
                        await model.reloadIfStale()
                    }
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
                            Task {
                                do {
                                    try await model.deleteRecipe(id: recipe.id)
                                    recipeToDelete = nil
                                } catch {
                                    deleteErrorMessage = error.localizedDescription
                                    recipeToDelete = nil
                                }
                            }
                        }
                    }
                    Button("Cancelar", role: .cancel) {
                        recipeToDelete = nil
                    }
                } message: {
                    if let recipe = recipeToDelete {
                        Text("Se eliminará la receta '\(recipe.recipe.name)'. Esta acción no se puede deshacer.")
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
        switch model.state {
        case .loading where model.isEmpty:
            ProgressView()
                .tint(Color.accentColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .error(let message) where model.isEmpty:
            ErrorStateView(message: message) {
                Task { await model.load() }
            }

        default:
            if model.isEmpty {
                ScrollView {
                    if model.isSearching {
                        ContentUnavailableView.search(text: model.query)
                            .padding(.top, 40)
                    } else {
                        ContentUnavailableView(
                            "Todavía no hay recetas",
                            systemImage: "book.closed",
                            description: Text("Arma una receta y te decimos cuánto te cuesta.")
                        )
                        .padding(.top, 40)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .refreshable {
                    await model.refresh()
                }
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
                        .onAppear {
                            Task {
                                await model.loadNextPageIfNeeded(currentItem: item)
                            }
                        }
                    }

                    if model.isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                                .tint(Color.accentColor)
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .refreshable {
                    await model.refresh()
                }
            }
        }
    }

    private func handleSearch(query: String) {
        searchTask?.cancel()
        searchTask = Task {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                // Borró la búsqueda: vuelve a la primera pantalla (desde la caché si está)
                await model.load()
            } else {
                try? await Task.sleep(nanoseconds: 300_000_000)
                if !Task.isCancelled {
                    await model.load()
                }
            }
        }
    }
}

/// Fila individual de receta en la lista.
struct RecipeRow: View {
    let item: RecipeListItem

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(item.recipe.name)
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
    NavigationStack {
        RecipesMockListContainer()
    }
}

#Preview("Letra AX3") {
    NavigationStack {
        RecipesMockListContainer()
    }
    .dynamicTypeSize(.accessibility3)
}

private struct RecipesMockListContainer: View {
    @State private var model = RecipesModel(mockItems: RecipeListItem.mockListItems)
    @State private var showingNew = false

    var body: some View {
        List {
            ForEach(model.items) { item in
                RecipeRow(item: item)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(.canvasBackground)
        .navigationTitle("Recetas")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AddToolbarButton(label: "Nueva receta") {
                    showingNew = true
                }
            }
        }
    }
}
#endif
