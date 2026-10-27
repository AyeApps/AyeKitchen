import SwiftUI

// MARK: - Modelo de Sección de Marcas

@Observable final class IngredientBrandsSectionModel {
    let ingredientId: String
    var presentations: [Presentation] = []
    var isLoading = false
    var errorMessage: String?

    init(ingredientId: String, initialPresentations: [Presentation]? = nil) {
        self.ingredientId = ingredientId
        if let initialPresentations {
            self.presentations = initialPresentations
        }
    }

    func loadBrands() async {
        isLoading = true
        errorMessage = nil
        do {
            let page: Page<Presentation> = try await NetworkService.shared.request(
                .get,
                "/presentations/",
                query: [
                    URLQueryItem(name: "ingredient_id", value: ingredientId),
                    URLQueryItem(name: "limit", value: "100")
                ]
            )
            self.presentations = page.items
            self.isLoading = false
        } catch {
            self.isLoading = false
            self.errorMessage = error.localizedDescription
        }
    }

    func deletePresentation(id: String) async throws {
        try await NetworkService.shared.requestNoContent(.delete, "/presentations/\(id)")
        presentations.removeAll { $0.id == id }
    }
}

// MARK: - Vista de Sección de Marcas

/// Sección de marcas y precios dentro de la lista de detalle de un ingrediente.
struct IngredientBrandsSection: View {
    let ingredient: Ingredient

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var model: IngredientBrandsSectionModel
    @State private var showingAddBrandSheet = false
    @State private var presentationToDelete: Presentation?
    @State private var showingDeleteConfirmation = false
    @State private var deleteErrorMessage: String?

    init(ingredient: Ingredient, initialPresentations: [Presentation]? = nil) {
        self.ingredient = ingredient
        self._model = State(initialValue: IngredientBrandsSectionModel(
            ingredientId: ingredient.id,
            initialPresentations: initialPresentations
        ))
    }

    var body: some View {
        Group {
            if model.isLoading && model.presentations.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if let errorMessage = model.errorMessage, model.presentations.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)
                    Button("Intentar de nuevo") {
                        Task {
                            await model.loadBrands()
                        }
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                }
            } else {
                if model.presentations.isEmpty {
                    Text("Agrega dónde compras este ingrediente y cuánto cuesta.")
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)
                } else {
                    ForEach(model.presentations) { presentation in
                        NavigationLink {
                            BrandDetailView(presentation: presentation) {
                                Task {
                                    await model.loadBrands()
                                }
                            }
                        } label: {
                            brandRow(presentation)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                presentationToDelete = presentation
                                showingDeleteConfirmation = true
                            } label: {
                                Label("Borrar", systemImage: "trash")
                            }
                        }
                    }
                }

                Button {
                    showingAddBrandSheet = true
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "plus.circle.fill")
                            .imageScale(.medium)
                        Text("Agregar marca")
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
        .task {
            if model.presentations.isEmpty && model.errorMessage == nil {
                await model.loadBrands()
            }
        }
        .sheet(isPresented: $showingAddBrandSheet) {
            BrandFormView(mode: .create(ingredient: ingredient)) { _ in
                Task {
                    await model.loadBrands()
                }
            }
        }
        .confirmationDialog(
            "¿Borrar \(presentationToDelete?.brand ?? "esta marca")?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Borrar", role: .destructive) {
                if let pres = presentationToDelete {
                    Task {
                        await performDelete(pres)
                    }
                }
            }
            Button("Cancelar", role: .cancel) {
                presentationToDelete = nil
            }
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

    private func brandRow(_ presentation: Presentation) -> some View {
        let titleText: String = {
            if let store = presentation.supplierName, !store.isEmpty {
                return "\(presentation.brand) · \(store)"
            }
            return presentation.brand
        }()

        let subtitleText: String = {
            let pkgStr = "\(Quantity.format(presentation.packageQuantity)) \(presentation.baseUnit.rawValue)"
            if let cents = presentation.latestPriceCents {
                let price = Money.format(cents: cents)
                if let age = ageDescription(days: presentation.priceAgeDays) {
                    return "\(price) por \(pkgStr) · \(age)"
                } else {
                    return "\(price) por \(pkgStr)"
                }
            } else {
                return "por \(pkgStr)"
            }
        }()

        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(titleText)
                        .font(.headline)
                        .foregroundStyle(.inkPrimary)
                    Text(subtitleText)
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)
                    chipsView(for: presentation)
                }
                .padding(.vertical, Spacing.xs)
            } else {
                HStack(alignment: .center, spacing: Spacing.sm) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(titleText)
                            .font(.headline)
                            .foregroundStyle(.inkPrimary)
                        Text(subtitleText)
                            .font(.subheadline)
                            .foregroundStyle(.inkMuted)
                    }
                    Spacer()
                    chipsView(for: presentation)
                }
                .padding(.vertical, Spacing.xs)
            }
        }
    }

    @ViewBuilder
    private func chipsView(for presentation: Presentation) -> some View {
        HStack(spacing: Spacing.xs) {
            if presentation.latestPriceCents == nil {
                Chip("Falta precio", tone: .warning)
            } else if presentation.priceIsStale {
                Chip("Precio viejo", tone: .warning)
            }
            if presentation.isCurrent {
                Chip("La que usamos", tone: .inProgress)
            }
        }
    }

    private func ageDescription(days: Int?) -> String? {
        guard let days else { return nil }
        if days <= 0 {
            return "hoy"
        } else if days == 1 {
            return "hace 1 día"
        } else {
            return "hace \(days) días"
        }
    }

    private func performDelete(_ presentation: Presentation) async {
        do {
            try await model.deletePresentation(id: presentation.id)
            presentationToDelete = nil
        } catch let apiError as APIError {
            if apiError.code == "IN_USE" {
                deleteErrorMessage = "Una receta usa esta marca. Cámbiala en la receta antes de borrarla."
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
private let mockIngredientForSection = Ingredient(
    id: "ing_preview",
    name: "Harina de trigo",
    baseUnit: .g,
    group: "Harinas",
    notes: nil,
    conversions: [],
    createdAt: Date(),
    updatedAt: Date()
)

private let mockPresentationsForSection: [Presentation] = [
    Presentation(
        id: "pres_1",
        ingredientId: "ing_preview",
        ingredientName: "Harina de trigo",
        brand: "Selecta",
        supplierId: "sup_1",
        supplierName: "Walmart",
        packageQuantity: "1000",
        baseUnit: .g,
        barcode: nil,
        latestPriceCents: 2350,
        latestPriceAt: Date(),
        costPerBaseUnit: "2.350000",
        isCurrent: true,
        priceAgeDays: 0,
        priceIsStale: false,
        createdAt: Date(),
        updatedAt: Date()
    ),
    Presentation(
        id: "pres_2",
        ingredientId: "ing_preview",
        ingredientName: "Harina de trigo",
        brand: "San Antonio",
        supplierId: "sup_2",
        supplierName: "Costco",
        packageQuantity: "1000",
        baseUnit: .g,
        barcode: nil,
        latestPriceCents: 2200,
        latestPriceAt: Date().addingTimeInterval(-45 * 86400),
        costPerBaseUnit: "2.200000",
        isCurrent: false,
        priceAgeDays: 45,
        priceIsStale: true,
        createdAt: Date(),
        updatedAt: Date()
    ),
    Presentation(
        id: "pres_3",
        ingredientId: "ing_preview",
        ingredientName: "Harina de trigo",
        brand: "Tres Estrellas",
        supplierId: nil,
        supplierName: nil,
        packageQuantity: "1000",
        baseUnit: .g,
        barcode: nil,
        latestPriceCents: nil,
        latestPriceAt: nil,
        costPerBaseUnit: nil,
        isCurrent: false,
        priceAgeDays: nil,
        priceIsStale: false,
        createdAt: Date(),
        updatedAt: Date()
    )
]

#Preview("Con marcas - Claro") {
    List {
        Section("Marcas y precios") {
            IngredientBrandsSection(
                ingredient: mockIngredientForSection,
                initialPresentations: mockPresentationsForSection
            )
        }
    }
}

#Preview("Sin marcas - Claro") {
    List {
        Section("Marcas y precios") {
            IngredientBrandsSection(
                ingredient: mockIngredientForSection,
                initialPresentations: []
            )
        }
    }
}

#Preview("Letra AX3") {
    List {
        Section("Marcas y precios") {
            IngredientBrandsSection(
                ingredient: mockIngredientForSection,
                initialPresentations: mockPresentationsForSection
            )
        }
    }
    .dynamicTypeSize(.accessibility3)
}
#endif
