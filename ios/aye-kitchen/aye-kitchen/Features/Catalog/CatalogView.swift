import SwiftUI
import TipKit
import KitchenDomain

/// Catálogo: lista de ingredientes agrupados con búsqueda y borrado local.
struct CatalogView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model: CatalogModel
    @State private var searchText = ""
    @State private var showingNewIngredient = false
    @State private var showingSuppliers = false
    @State private var ingredientToDelete: CatalogIngredient?
    @State private var showingDeleteConfirmation = false
    @State private var deleteErrorMessage: String?

    init(model: CatalogModel = CatalogModel()) {
        self._model = State(initialValue: model)
    }

    init(store: LocalStore) {
        self._model = State(initialValue: CatalogModel(store: store))
    }

    var body: some View {
        NavigationStack {
            content
                .background(.canvasBackground)
                .navigationTitle("Catálogo")
                .searchable(text: $searchText, prompt: "Buscar ingrediente")
                .onChange(of: searchText) { _, newValue in
                    model.searchText = newValue
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
                    IngredientFormView(mode: .create)
                }
                .confirmationDialog(
                    "¿Borrar \(ingredientToDelete?.name ?? "este ingrediente")?",
                    isPresented: $showingDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Borrar", role: .destructive) {
                        if let ingredient = ingredientToDelete {
                            performDelete(ingredient)
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
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.ingredients.isEmpty {
            ScrollView {
                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ContentUnavailableView {
                        Label("Tu catálogo está vacío", systemImage: "square.grid.2x2")
                    } description: {
                        Text("Agrega los ingredientes que compras y dónde los compras.")
                    } actions: {
                        Button {
                            showingNewIngredient = true
                        } label: {
                            Text("Agregar ingrediente")
                        }
                        .buttonStyle(.kitchenPrimary)
                        .padding(.horizontal, Spacing.xxl)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                TipView(CatalogBrandsTip())
                    .tipBackground(.surfaceCard)

                ForEach(model.sections) { section in
                    Section(section.title) {
                        ForEach(section.items) { ingredient in
                            NavigationLink {
                                IngredientDetailView(ingredientId: ingredient.id)
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
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func ingredientSubtitle(for ingredient: CatalogIngredient) -> some View {
        let brandsCount = ingredient.brandsCount
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
    }

    private func performDelete(_ ingredient: CatalogIngredient) {
        do {
            try model.deleteIngredient(id: ingredient.id)
            ingredientToDelete = nil
        } catch let domainError as DomainError {
            if domainError.code == "IN_USE" {
                deleteErrorMessage = "No se puede borrar: una receta lo usa."
            } else {
                deleteErrorMessage = domainError.detail
            }
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Claro") {
    CatalogView(store: .preview())
}

#Preview("Letra AX3") {
    CatalogView(store: .preview())
        .dynamicTypeSize(.accessibility3)
}
#endif
