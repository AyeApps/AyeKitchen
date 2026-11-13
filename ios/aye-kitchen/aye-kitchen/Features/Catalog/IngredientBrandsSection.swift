import SwiftUI
import TipKit
import KitchenDomain

// MARK: - Vista de Sección de Marcas

/// Sección de marcas y precios dentro de la lista de detalle de un ingrediente.
struct IngredientBrandsSection: View {
    let ingredientId: String
    private let store: LocalStore

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showingAddBrandSheet = false
    @State private var presentationToDelete: CatalogPresentation?
    @State private var showingDeleteConfirmation = false
    @State private var deleteErrorMessage: String?

    init(ingredientId: String, store: LocalStore = .shared) {
        self.ingredientId = ingredientId
        self.store = store
    }

    var presentations: [CatalogPresentation] {
        (try? store.data.presentations(forIngredient: ingredientId)) ?? []
    }

    var body: some View {
        Group {
            if presentations.isEmpty {
                Text("Agrega dónde compras este ingrediente y cuánto cuesta.")
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
            } else {
                TipView(IngredientCurrentBrandTip())
                    .tipBackground(.surfaceCard)

                ForEach(presentations) { presentation in
                    NavigationLink {
                        BrandDetailView(presentationId: presentation.id, store: store)
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
        .onAppear {
            IngredientCurrentBrandTip.ingredientHasBrands = !presentations.isEmpty
        }
        .onChange(of: presentations.isEmpty) { _, isEmpty in
            IngredientCurrentBrandTip.ingredientHasBrands = !isEmpty
        }
        .sheet(isPresented: $showingAddBrandSheet) {
            BrandFormView(mode: .create(ingredientId: ingredientId), store: store)
        }
        .confirmationDialog(
            "¿Borrar \(presentationToDelete?.brand ?? "esta marca")?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Borrar", role: .destructive) {
                if let pres = presentationToDelete {
                    performDelete(pres)
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

    private func brandRow(_ presentation: CatalogPresentation) -> some View {
        let titleText: String = {
            if let store = presentation.supplierName, !store.isEmpty {
                return "\(presentation.brand) · \(store)"
            }
            return presentation.brand
        }()

        let subtitleText: String = {
            let pkgStr = packageText(for: presentation)
            if let cents = presentation.latestPriceCents {
                let price = Money.format(cents: cents)
                let base: String = {
                    if let age = ageDescription(days: presentation.priceAgeDays) {
                        return "\(price) por \(pkgStr) · \(age)"
                    } else {
                        return "\(price) por \(pkgStr)"
                    }
                }()
                if let costPerBase = presentation.costPerBaseUnit,
                   let perUnit = Money.formatPerUnit(costPerBaseUnit: costPerBase, baseUnit: presentation.baseUnit) {
                    return "\(base) · \(perUnit)"
                } else {
                    return base
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
                        .fixedSize(horizontal: false, vertical: true)
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
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    chipsView(for: presentation)
                }
                .padding(.vertical, Spacing.xs)
            }
        }
    }

    @ViewBuilder
    private func chipsView(for presentation: CatalogPresentation) -> some View {
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

    private func performDelete(_ presentation: CatalogPresentation) {
        do {
            try store.mutate { data, ctx in
                try data.deletePresentation(id: presentation.id, ctx: ctx)
            }
            presentationToDelete = nil
        } catch let domainError as DomainError {
            if domainError.code == "IN_USE" {
                deleteErrorMessage = "Una receta usa esta marca. Cámbiala en la receta antes de borrarla."
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
#Preview("Con marcas - Claro") {
    List {
        Section("Marcas y precios") {
            IngredientBrandsSection(
                ingredientId: "ing-harina",
                store: .preview()
            )
        }
    }
}

#Preview("Sin marcas - Claro") {
    List {
        Section("Marcas y precios") {
            IngredientBrandsSection(
                ingredientId: "ing-chispas",
                store: .preview()
            )
        }
    }
}

#Preview("Letra AX3") {
    List {
        Section("Marcas y precios") {
            IngredientBrandsSection(
                ingredientId: "ing-harina",
                store: .preview()
            )
        }
    }
    .dynamicTypeSize(.accessibility3)
}
#endif
