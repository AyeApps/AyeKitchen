import SwiftUI

/// Catálogo: lista de ingredientes agrupados con búsqueda, paginación y borrado.
struct CatalogView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: CatalogModel
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var showingNewIngredient = false
    @State private var showingSuppliers = false
    @State private var ingredientToDelete: Ingredient?
    @State private var showingDeleteConfirmation = false
    @State private var deleteErrorMessage: String?
    @State private var isVisible = false

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
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            await model.search(query: "")
                        } else {
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            if !Task.isCancelled {
                                await model.search(query: newValue)
                            }
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showingSuppliers = true
                        } label: {
                            Image(systemName: "storefront")
                        }
                        .accessibilityLabel("Tiendas")
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        AddToolbarButton(label: "Agregar ingrediente") {
                            showingNewIngredient = true
                        }
                    }
                }
                .sheet(isPresented: $showingSuppliers) {
                    SuppliersView()
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
                                        ingredientSubtitle(for: ingredient)
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

    @ViewBuilder
    private func ingredientSubtitle(for ingredient: Ingredient) -> some View {
        if let brandsCount = ingredient.brandsCount {
            if brandsCount > 0 {
                let countText = brandsCount == 1 ? "1 marca" : "\(brandsCount) marcas"
                let brandDetail: String? = {
                    guard let currentBrand = ingredient.currentBrand,
                          let costPerBaseUnit = currentBrand.costPerBaseUnit,
                          let formattedPrice = Money.formatPerUnit(costPerBaseUnit: costPerBaseUnit, baseUnit: ingredient.baseUnit)
                    else {
                        return nil
                    }
                    return "Usamos \(currentBrand.brand) · \(formattedPrice)"
                }()

                if let brandDetail {
                    if dynamicTypeSize.isAccessibilitySize {
                        Text(countText)
                            .font(.subheadline)
                            .foregroundStyle(.inkMuted)
                        Text(brandDetail)
                            .font(.subheadline)
                            .foregroundStyle(.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("\(countText) · \(brandDetail)")
                            .font(.subheadline)
                            .foregroundStyle(.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(countText)
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)
                }
            } else {
                Text("Sin marcas todavía")
                    .font(.subheadline)
                    .foregroundStyle(.warningText)
            }
        } else {
            Text(ingredient.buyingUnitDescription)
                .font(.subheadline)
                .foregroundStyle(.inkMuted)
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
        updatedAt: Date(),
        brandsCount: 3,
        currentBrand: IngredientCurrentBrand(
            presentationId: "pres_1",
            brand: "Selecta",
            supplierName: "Walmart",
            costPerBaseUnit: "2.350000"
        )
    ),
    Ingredient(
        id: "ing_2",
        name: "Harina de almendra",
        baseUnit: .g,
        group: "Harinas",
        notes: nil,
        conversions: [],
        createdAt: Date(),
        updatedAt: Date(),
        brandsCount: 0,
        currentBrand: nil
    ),
    Ingredient(
        id: "ing_3",
        name: "Leche entera",
        baseUnit: .ml,
        group: "Lácteos",
        notes: nil,
        conversions: [],
        createdAt: Date(),
        updatedAt: Date(),
        brandsCount: nil,
        currentBrand: nil
    ),
    Ingredient(
        id: "ing_4",
        name: "Huevo",
        baseUnit: .pz,
        group: nil,
        notes: nil,
        conversions: [],
        createdAt: Date(),
        updatedAt: Date(),
        brandsCount: 1,
        currentBrand: IngredientCurrentBrand(
            presentationId: "pres_4",
            brand: "San Juan",
            supplierName: nil,
            costPerBaseUnit: "3.200000"
        )
    ),
    Ingredient(
        id: "ing_5",
        name: "Vainilla líquida",
        baseUnit: .ml,
        group: nil,
        notes: nil,
        conversions: [],
        createdAt: Date(),
        updatedAt: Date(),
        brandsCount: 0,
        currentBrand: nil
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
