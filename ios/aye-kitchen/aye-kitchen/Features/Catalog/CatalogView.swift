import SwiftUI

/// Catálogo: lista de ingredientes agrupados con búsqueda, paginación y borrado.
struct CatalogView: View {
    @State private var model: CatalogModel
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var showingNewIngredient = false
    @State private var ingredientToDelete: Ingredient?
    @State private var showingDeleteConfirmation = false
    @State private var deleteErrorMessage: String?

    init(model: CatalogModel = CatalogModel()) {
        self._model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            content
                .background(.canvasBackground)
                .navigationTitle("Catálogo")
                .searchable(text: $searchText, prompt: "Buscar ingrediente")
                .onChange(of: searchText) { _, newValue in
                    searchTask?.cancel()
                    searchTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        if !Task.isCancelled {
                            await model.search(query: newValue)
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        AddToolbarButton(label: "Agregar ingrediente") {
                            showingNewIngredient = true
                        }
                    }
                }
                .sheet(isPresented: $showingNewIngredient) {
                    IngredientFormView(mode: .create) { created in
                        model.addIngredient(created)
                    }
                }
                .confirmationDialog(
                    "¿Borrar \(ingredientToDelete?.name ?? "este ingrediente")?",
                    isPresented: $showingDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Borrar", role: .destructive) {
                        if let ingredient = ingredientToDelete {
                            Task {
                                await performDelete(ingredient)
                            }
                        }
                    }
                    Button("Cancelar", role: .cancel) {
                        ingredientToDelete = nil
                    }
                } message: {
                    Text("También se borran sus marcas.")
                }
                .alert("No se pudo borrar", isPresented: Binding(
                    get: { deleteErrorMessage != nil },
                    set: { if !$0 { deleteErrorMessage = nil } }
                )) {
                    Button("Aceptar", role: .cancel) {
                        deleteErrorMessage = nil
                    }
                } message: {
                    if let deleteErrorMessage {
                        Text(deleteErrorMessage)
                    }
                }
                .task {
                    await model.loadInitial()
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading where model.ingredients.isEmpty:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .error(let message) where model.ingredients.isEmpty:
            ErrorStateView(message: message) {
                Task {
                    await model.loadInitial()
                }
            }

        case .loaded, .loading, .idle, .error:
            if model.ingredients.isEmpty {
                ScrollView {
                    if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        ContentUnavailableView(
                            "Tu catálogo está vacío",
                            systemImage: "square.grid.2x2",
                            description: Text("Agrega los ingredientes que compras y dónde los compras.")
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .refreshable {
                    await model.refresh()
                }
            } else {
                List {
                    ForEach(model.sections) { section in
                        Section(section.title) {
                            ForEach(section.items) { ingredient in
                                NavigationLink {
                                    IngredientDetailView(
                                        ingredient: ingredient,
                                        onUpdate: { updated in
                                            model.updateIngredient(updated)
                                        },
                                        onDelete: { deletedId in
                                            model.removeIngredient(id: deletedId)
                                        }
                                    )
                                } label: {
                                    VStack(alignment: .leading, spacing: Spacing.xs) {
                                        Text(ingredient.name)
                                            .font(.headline)
                                            .foregroundStyle(.inkPrimary)
                                        Text(ingredient.buyingUnitDescription)
                                            .font(.subheadline)
                                            .foregroundStyle(.inkMuted)
                                    }
                                    .padding(.vertical, Spacing.xs)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        ingredientToDelete = ingredient
                                        showingDeleteConfirmation = true
                                    } label: {
                                        Label("Borrar", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }

                    if model.hasMore {
                        Section {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .onAppear {
                                Task {
                                    await model.loadNextPage()
                                }
                            }
                        }
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

    private func performDelete(_ ingredient: Ingredient) async {
        do {
            try await model.deleteIngredient(ingredient)
            ingredientToDelete = nil
        } catch let apiError as APIError {
            if apiError.code == "IN_USE" {
                deleteErrorMessage = "No se puede borrar: una receta lo usa."
            } else {
                deleteErrorMessage = apiError.localizedDescription
            }
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
    }
}

// MARK: - Previews

#if DEBUG
private let mockCatalogIngredients: [Ingredient] = [
    Ingredient(
        id: "ing_1",
        name: "Harina de trigo",
        baseUnit: .g,
        group: "Harinas",
        notes: nil,
        conversions: [
            IngredientConversion(unitId: "u_tz", unitName: "taza", quantityInBase: "125")
        ],
        createdAt: Date(),
        updatedAt: Date()
    ),
    Ingredient(
        id: "ing_2",
        name: "Harina de almendra",
        baseUnit: .g,
        group: "Harinas",
        notes: nil,
        conversions: [],
        createdAt: Date(),
        updatedAt: Date()
    ),
    Ingredient(
        id: "ing_3",
        name: "Leche entera",
        baseUnit: .ml,
        group: "Lácteos",
        notes: nil,
        conversions: [],
        createdAt: Date(),
        updatedAt: Date()
    ),
    Ingredient(
        id: "ing_4",
        name: "Huevo",
        baseUnit: .pz,
        group: nil,
        notes: nil,
        conversions: [],
        createdAt: Date(),
        updatedAt: Date()
    ),
    Ingredient(
        id: "ing_5",
        name: "Vainilla líquida",
        baseUnit: .ml,
        group: nil,
        notes: nil,
        conversions: [],
        createdAt: Date(),
        updatedAt: Date()
    )
]

#Preview("Claro") {
    CatalogView(model: CatalogModel(mockIngredients: mockCatalogIngredients))
}

#Preview("Letra AX3") {
    CatalogView(model: CatalogModel(mockIngredients: mockCatalogIngredients))
        .dynamicTypeSize(.accessibility3)
}
#endif
