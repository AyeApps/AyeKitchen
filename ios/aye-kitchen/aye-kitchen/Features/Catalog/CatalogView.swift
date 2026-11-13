import SwiftUI
import TipKit
import KitchenDomain

/// Catálogo: lista de ingredientes agrupados con búsqueda, filtros, orden y borrado local.
struct CatalogView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model: CatalogModel
    @State private var showingFilters = false
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

    private var isFilterActive: Bool {
        model.filter.hasFilters || model.filter.sort != .group
    }

    var body: some View {
        NavigationStack {
            content
                .background(.canvasBackground)
                .navigationTitle("Catálogo")
                .searchable(text: $model.filter.query, prompt: "Buscar ingrediente, marca o tienda")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showingSuppliers = true
                        } label: {
                            Image(systemName: "storefront")
                        }
                        .accessibilityLabel("Tiendas")
                        .popoverTip(CatalogStoresTip(), arrowEdge: .top)
                    }

                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            showingFilters = true
                        } label: {
                            Image(systemName: isFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        }
                        .accessibilityLabel("Filtrar y ordenar")

                        AddToolbarButton(label: "Agregar ingrediente") {
                            showingNewIngredient = true
                        }
                    }
                }
                .sheet(isPresented: $showingFilters) {
                    CatalogFilterSheet(model: model)
                        .presentationDetents([.medium, .large])
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
        VStack(spacing: 0) {
            if model.hasAnyIngredient && model.filter.hasFilters {
                activeFiltersBar
            }

            if model.items.isEmpty {
                emptyStateView
            } else {
                listView
            }
        }
    }

    // MARK: - Barra de filtros activos

    private var activeFiltersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                // 1. Tienda
                switch model.filter.store {
                case .all:
                    EmptyView()
                case .store(let storeId):
                    let storeName = model.suppliers.first(where: { $0.id == storeId })?.name ?? "Tienda"
                    CatalogFilterCapsule(title: storeName) {
                        model.filter.store = .all
                    }
                case .noStore:
                    CatalogFilterCapsule(title: "Sin tienda") {
                        model.filter.store = .all
                    }
                }

                // 2. Grupo
                if let group = model.filter.group, !group.isEmpty {
                    CatalogFilterCapsule(title: group) {
                        model.filter.group = nil
                    }
                }

                // 3. Precio
                switch model.filter.price {
                case .all:
                    EmptyView()
                case .withoutPrice:
                    CatalogFilterCapsule(title: "Sin precio") {
                        model.filter.price = .all
                    }
                case .stale:
                    CatalogFilterCapsule(title: "Precio viejo") {
                        model.filter.price = .all
                    }
                case .range(let minCents, let maxCents):
                    let priceTitle: String = {
                        switch (minCents, maxCents) {
                        case let (.some(min), .some(max)):
                            return "\(formatCentsShort(min)) a \(formatCentsShort(max))"
                        case let (.some(min), .none):
                            return "Desde \(formatCentsShort(min))"
                        case let (.none, .some(max)):
                            return "Hasta \(formatCentsShort(max))"
                        case (.none, .none):
                            return "Entre…"
                        }
                    }()
                    CatalogFilterCapsule(title: priceTitle) {
                        model.filter.price = .all
                    }
                }

                // 4. Quitar todo
                Button("Quitar todo") {
                    model.clearFilters()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
                .padding(.leading, Spacing.xs)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
        }
    }

    private func formatCentsShort(_ cents: Int) -> String {
        if cents % 100 == 0 {
            return "$\(cents / 100)"
        } else {
            return Money.format(cents: cents)
        }
    }

    // MARK: - Estado vacío

    private var emptyStateView: some View {
        ScrollView {
            if !model.hasAnyIngredient {
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
            } else if model.filter.hasFilters {
                ContentUnavailableView {
                    Label("Nada coincide con tus filtros", systemImage: "line.3.horizontal.decrease.circle")
                } actions: {
                    Button("Quitar filtros") {
                        model.clearFilters()
                    }
                    .buttonStyle(.kitchenPrimary)
                    .padding(.horizontal, Spacing.xxl)
                }
            } else {
                ContentUnavailableView.search(text: model.filter.query)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Lista

    private var listView: some View {
        List {
            TipView(CatalogBrandsTip())
                .tipBackground(.surfaceCard)

            ForEach(model.sections) { section in
                if section.title.isEmpty {
                    Section {
                        sectionRows(for: section.items)
                    }
                } else {
                    Section(section.title) {
                        sectionRows(for: section.items)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func sectionRows(for items: [CatalogListItem]) -> some View {
        ForEach(items) { item in
            NavigationLink {
                IngredientDetailView(ingredientId: item.id)
            } label: {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(item.ingredient.name)
                        .font(.headline)
                        .foregroundStyle(.inkPrimary)
                    itemSubtitle(for: item)
                }
                .padding(.vertical, Spacing.xs)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    ingredientToDelete = item.ingredient
                    showingDeleteConfirmation = true
                } label: {
                    Label("Borrar", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Subtítulo del renglón

    @ViewBuilder
    private func itemSubtitle(for item: CatalogListItem) -> some View {
        if item.highlightsBrand, let brand = item.shownBrand {
            highlightedBrandSubtitle(for: brand)
        } else {
            ingredientSubtitle(for: item.ingredient)
        }
    }

    @ViewBuilder
    private func highlightedBrandSubtitle(for brand: CatalogPresentation) -> some View {
        let brandAndStore: String = {
            let storeName = brand.supplierName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let storeName, !storeName.isEmpty {
                return "\(brand.brand) · \(storeName)"
            } else {
                return brand.brand
            }
        }()

        let pricePart: String = {
            if let cents = brand.latestPriceCents {
                let formattedPrice = Money.format(cents: cents)
                let package = packageText(for: brand)
                return "\(formattedPrice) por \(package)"
            } else {
                return "Sin precio"
            }
        }()

        if dynamicTypeSize.isAccessibilitySize {
            Text(brandAndStore)
                .font(.subheadline)
                .foregroundStyle(.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            if brand.priceIsStale {
                (Text(pricePart).foregroundStyle(.inkMuted) + Text(" · precio viejo").foregroundStyle(.warningText))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(pricePart)
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            let fullSubtitle = "\(brandAndStore) · \(pricePart)"
            if brand.priceIsStale {
                (Text(fullSubtitle).foregroundStyle(.inkMuted) + Text(" · precio viejo").foregroundStyle(.warningText))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(fullSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

// MARK: - Cápsula de Filtro

private struct CatalogFilterCapsule: View {
    let title: String
    let onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: Spacing.xs) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.inkPrimary)

                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.inkMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.surfaceCard, in: .capsule)
            .overlay {
                Capsule()
                    .strokeBorder(Color.borderInput, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Quitar filtro \(title)")
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
