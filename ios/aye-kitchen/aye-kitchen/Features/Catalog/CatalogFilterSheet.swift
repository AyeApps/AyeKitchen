import SwiftUI
import KitchenDomain

/// Hoja para filtrar y ordenar los ingredientes del catálogo (Bloque I33).
struct CatalogFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var model: CatalogModel

    @State private var priceOption: PriceOption
    @State private var minPriceText: String
    @State private var maxPriceText: String

    private enum PriceOption: Hashable {
        case all
        case withoutPrice
        case stale
        case range
    }

    init(model: CatalogModel) {
        self.model = model
        let (initialOption, initialMin, initialMax) = Self.parsePriceFilter(model.filter.price)
        _priceOption = State(initialValue: initialOption)
        _minPriceText = State(initialValue: initialMin)
        _maxPriceText = State(initialValue: initialMax)
    }

    var body: some View {
        NavigationStack {
            Form {
                sortSection
                storeSection
                groupSection
                priceSection
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Filtrar y ordenar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Quitar filtros") {
                        model.clearFilters()
                        priceOption = .all
                        minPriceText = ""
                        maxPriceText = ""
                    }
                    .disabled(!model.filter.hasFilters)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onChange(of: priceOption) { _, newOption in
                switch newOption {
                case .all:
                    model.filter.price = .all
                case .withoutPrice:
                    model.filter.price = .withoutPrice
                case .stale:
                    model.filter.price = .stale
                case .range:
                    applyPriceRange()
                }
            }
        }
    }

    // MARK: - Secciones

    private var sortSection: some View {
        Section("Ordenar") {
            Picker("Ordenar", selection: $model.filter.sort) {
                Text("Por grupo").tag(CatalogSort.group)
                Text("Por nombre (A–Z)").tag(CatalogSort.name)
                Text("Precio más bajo").tag(CatalogSort.priceLowToHigh)
                Text("Precio más alto").tag(CatalogSort.priceHighToLow)
                Text("Precio más viejo primero").tag(CatalogSort.oldestPrice)
            }
            .labelsHidden()
            .pickerStyle(.inline)
        }
    }

    private var storeSection: some View {
        Section("Tienda") {
            Picker("Tienda", selection: $model.filter.store) {
                Text("Todas").tag(CatalogStoreFilter.all)
                ForEach(model.suppliers) { supplier in
                    Text(supplier.name).tag(CatalogStoreFilter.store(id: supplier.id))
                }
                Text("Sin tienda").tag(CatalogStoreFilter.noStore)
            }
            .labelsHidden()
            .pickerStyle(.inline)
        }
    }

    @ViewBuilder
    private var groupSection: some View {
        if !model.groups.isEmpty {
            Section("Grupo") {
                Picker("Grupo", selection: $model.filter.group) {
                    Text("Todos").tag(Optional<String>.none)
                    ForEach(model.groups, id: \.self) { group in
                        Text(group).tag(Optional<String>.some(group))
                    }
                }
                .labelsHidden()
                .pickerStyle(.inline)
            }
        }
    }

    private var priceSection: some View {
        Section("Precio del paquete") {
            Picker("Precio del paquete", selection: $priceOption) {
                Text("Todos").tag(PriceOption.all)
                Text("Sin precio").tag(PriceOption.withoutPrice)
                Text("Precio viejo").tag(PriceOption.stale)
                Text("Entre…").tag(PriceOption.range)
            }
            .labelsHidden()
            .pickerStyle(.inline)

            if priceOption == .range {
                rangeFields
            }
        }
    }

    @ViewBuilder
    private var rangeFields: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Desde")
                    .font(.body)
                    .foregroundStyle(.inkPrimary)
                HStack(spacing: Spacing.xs) {
                    Text("$")
                        .foregroundStyle(.inkSecondary)
                    TextField("0.00", text: $minPriceText)
                        .keyboardType(.decimalPad)
                        .onChange(of: minPriceText) { _, _ in
                            applyPriceRange()
                        }
                }
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Hasta")
                    .font(.body)
                    .foregroundStyle(.inkPrimary)
                HStack(spacing: Spacing.xs) {
                    Text("$")
                        .foregroundStyle(.inkSecondary)
                    TextField("0.00", text: $maxPriceText)
                        .keyboardType(.decimalPad)
                        .onChange(of: maxPriceText) { _, _ in
                            applyPriceRange()
                        }
                }
            }
        } else {
            HStack {
                Text("Desde")
                    .font(.body)
                    .foregroundStyle(.inkPrimary)
                Spacer()
                HStack(spacing: Spacing.xs) {
                    Text("$")
                        .foregroundStyle(.inkSecondary)
                    TextField("0.00", text: $minPriceText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: minPriceText) { _, _ in
                            applyPriceRange()
                        }
                }
            }

            HStack {
                Text("Hasta")
                    .font(.body)
                    .foregroundStyle(.inkPrimary)
                Spacer()
                HStack(spacing: Spacing.xs) {
                    Text("$")
                        .foregroundStyle(.inkSecondary)
                    TextField("0.00", text: $maxPriceText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: maxPriceText) { _, _ in
                            applyPriceRange()
                        }
                }
            }
        }

        Text("Es el precio de todo el paquete de la marca que se muestra.")
            .font(.footnote)
            .foregroundStyle(.inkMuted)
    }

    // MARK: - Helpers

    private func applyPriceRange() {
        guard priceOption == .range else { return }
        let trimmedMin = minPriceText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "$", with: "")
        let minCents = trimmedMin.isEmpty ? nil : RecordPriceModel.parsePriceCents(trimmedMin)

        let trimmedMax = maxPriceText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "$", with: "")
        let maxCents = trimmedMax.isEmpty ? nil : RecordPriceModel.parsePriceCents(trimmedMax)

        model.filter.price = .range(minCents: minCents, maxCents: maxCents)
    }

    private static func parsePriceFilter(_ filter: CatalogPriceFilter) -> (PriceOption, String, String) {
        switch filter {
        case .all:
            return (.all, "", "")
        case .withoutPrice:
            return (.withoutPrice, "", "")
        case .stale:
            return (.stale, "", "")
        case .range(let minCents, let maxCents):
            let minStr = minCents.map { cents in
                if cents % 100 == 0 { return "\(cents / 100)" }
                return "\(Decimal(cents) / 100)"
            } ?? ""
            let maxStr = maxCents.map { cents in
                if cents % 100 == 0 { return "\(cents / 100)" }
                return "\(Decimal(cents) / 100)"
            } ?? ""
            return (.range, minStr, maxStr)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Claro") {
    CatalogFilterSheet(model: CatalogModel(store: .preview()))
}

#Preview("Letra AX3") {
    CatalogFilterSheet(model: CatalogModel(store: .preview()))
        .dynamicTypeSize(.accessibility3)
}
#endif
