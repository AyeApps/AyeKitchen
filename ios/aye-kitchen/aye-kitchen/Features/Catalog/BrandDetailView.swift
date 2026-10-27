import SwiftUI

// MARK: - Cuerpos de petición (docs/api-contract.md)

nonisolated struct PriceRecordCreateRequest: Encodable, Sendable {
    let priceCents: Int
    let recordedAt: Date
    let note: String?
}

// MARK: - Modelo de Detalle de Marca

@Observable final class BrandDetailModel: @unchecked Sendable {
    var presentation: Presentation
    var prices: [PriceRecord] = []
    var isLoadingPrices = false
    var errorMessage: String?

    init(presentation: Presentation, mockPrices: [PriceRecord]? = nil) {
        self.presentation = presentation
        if let mockPrices {
            self.prices = mockPrices
        }
    }

    func loadPrices() async {
        isLoadingPrices = true
        errorMessage = nil
        do {
            let list: [PriceRecord] = try await NetworkService.shared.request(
                .get,
                "/presentations/\(presentation.id)/prices"
            )
            self.prices = list
            self.isLoadingPrices = false
        } catch {
            self.isLoadingPrices = false
            self.errorMessage = error.localizedDescription
        }
    }

    func reload() async {
        do {
            async let presTask: Presentation = NetworkService.shared.request(
                .get,
                "/presentations/\(presentation.id)"
            )
            async let pricesTask: [PriceRecord] = NetworkService.shared.request(
                .get,
                "/presentations/\(presentation.id)/prices"
            )

            let (updatedPres, updatedPrices) = try await (presTask, pricesTask)
            self.presentation = updatedPres
            self.prices = updatedPrices
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Vista de Detalle de Marca

/// Detalle de la marca con precio actual, tarjeta suave, registro de nuevo precio e historial.
struct BrandDetailView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var model: BrandDetailModel
    @State private var showingEditSheet = false
    @State private var showingRecordPriceSheet = false

    var onBrandChangedOrDeleted: (() -> Void)?

    init(
        presentation: Presentation,
        mockPrices: [PriceRecord]? = nil,
        onBrandChangedOrDeleted: (() -> Void)? = nil
    ) {
        self._model = State(initialValue: BrandDetailModel(
            presentation: presentation,
            mockPrices: mockPrices
        ))
        self.onBrandChangedOrDeleted = onBrandChangedOrDeleted
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                priceCard
                registerPriceButton
                priceHistorySection
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxl)
        }
        .background(.canvasBackground)
        .navigationTitle(model.presentation.brand)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Editar") {
                    showingEditSheet = true
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            BrandFormView(mode: .edit(presentation: model.presentation)) { updated in
                model.presentation = updated
                onBrandChangedOrDeleted?()
            }
        }
        .sheet(isPresented: $showingRecordPriceSheet) {
            RecordPriceSheet(presentationId: model.presentation.id) {
                Task {
                    await model.reload()
                    onBrandChangedOrDeleted?()
                }
            }
        }
        .task {
            if model.prices.isEmpty {
                await model.loadPrices()
            }
        }
    }

    // MARK: - Tarjeta de Precio

    private var priceCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let cents = model.presentation.latestPriceCents {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(Money.format(cents: cents))
                            .font(.title.weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(.inkPrimary)
                        if model.presentation.priceIsStale {
                            Chip("Precio viejo", tone: .warning)
                        }
                    }
                } else {
                    HStack(alignment: .center) {
                        Text(Money.format(cents: cents))
                            .font(.title.weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(.inkPrimary)
                        Spacer()
                        if model.presentation.priceIsStale {
                            Chip("Precio viejo", tone: .warning)
                        }
                    }
                }

                Text(packageStoreAndAgeText)
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
            } else {
                Text("Todavía no tiene precio.")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(.inkPrimary)

                Text(packageAndStoreText)
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
            }
        }
        .softCard()
    }

    private var packageStoreAndAgeText: String {
        var parts: [String] = []
        let pkg = "por \(Quantity.format(model.presentation.packageQuantity)) \(model.presentation.baseUnit.rawValue)"
        parts.append(pkg)

        if let store = model.presentation.supplierName, !store.isEmpty {
            parts.append(store)
        }

        if let age = ageDescription(days: model.presentation.priceAgeDays) {
            parts.append(age)
        }

        return parts.joined(separator: " · ")
    }

    private var packageAndStoreText: String {
        var parts: [String] = []
        let pkg = "por \(Quantity.format(model.presentation.packageQuantity)) \(model.presentation.baseUnit.rawValue)"
        parts.append(pkg)

        if let store = model.presentation.supplierName, !store.isEmpty {
            parts.append(store)
        }

        return parts.joined(separator: " · ")
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

    // MARK: - Botón Registrar Precio

    private var registerPriceButton: some View {
        Button("Registrar precio") {
            showingRecordPriceSheet = true
        }
        .buttonStyle(.kitchenPrimary)
    }

    // MARK: - Historial de Precios

    private var priceHistorySection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Historial de precios")
                .sectionTitleStyle()

            if model.isLoadingPrices && model.prices.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, Spacing.lg)
            } else if model.prices.isEmpty {
                Text("Todavía no has registrado ningún precio.")
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
                    .padding(.vertical, Spacing.sm)
            } else {
                RowGroup {
                    ForEach(Array(model.prices.enumerated()), id: \.element.id) { index, priceRecord in
                        priceHistoryRow(record: priceRecord, index: index)
                    }
                }
            }
        }
    }

    private func priceHistoryRow(record: PriceRecord, index: Int) -> some View {
        let diffText = priceDifferenceText(currentIndex: index)

        return VStack(alignment: .leading, spacing: Spacing.xs) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(Money.format(cents: record.priceCents))
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(.inkPrimary)

                    if let diffText {
                        Text(diffText)
                            .font(.subheadline)
                            .foregroundStyle(.inkMuted)
                    }

                    Text(formatRecordDate(record.recordedAt))
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(Money.format(cents: record.priceCents))
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(.inkPrimary)

                    if let diffText {
                        Text(diffText)
                            .font(.subheadline)
                            .foregroundStyle(.inkMuted)
                    }

                    Spacer()

                    Text(formatRecordDate(record.recordedAt))
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)
                }
            }

            if let note = record.note, !note.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.inkSecondary)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func priceDifferenceText(currentIndex: Int) -> String? {
        // La lista de precios viene ordenada descendente por recorded_at (el más nuevo en index 0).
        // El precio anterior en el tiempo está en currentIndex + 1.
        guard currentIndex + 1 < model.prices.count else {
            return nil
        }
        let currentCents = model.prices[currentIndex].priceCents
        let previousCents = model.prices[currentIndex + 1].priceCents
        let diffCents = currentCents - previousCents

        if diffCents > 0 {
            return "Subió \(Money.format(cents: diffCents))"
        } else if diffCents < 0 {
            return "Bajó \(Money.format(cents: abs(diffCents)))"
        } else {
            return "Igual"
        }
    }

    private func formatRecordDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "es_MX")))
    }
}

// MARK: - Hoja para Registrar Precio

struct RecordPriceSheet: View {
    let presentationId: String
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var priceText = ""
    @State private var recordedAt = Date()
    @State private var noteText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var parsedPriceCents: Int? {
        let normalized = priceText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty,
              let decimal = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
              decimal >= 0 else {
            return nil
        }
        var centsDecimal = decimal * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &centsDecimal, 0, .plain)
        return (rounded as NSDecimalNumber).intValue
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    KitchenTextField(
                        label: "Precio",
                        text: $priceText,
                        keyboard: .decimalPad
                    )

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("¿Cuándo lo pagaste?")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.inkPrimary)

                        DatePicker(
                            "¿Cuándo lo pagaste?",
                            selection: $recordedAt,
                            in: ...Date(),
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .environment(\.locale, Locale(identifier: "es_MX"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 56)
                        .background(.surfaceInput, in: .rect(cornerRadius: Radius.card))
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.card)
                                .strokeBorder(.borderInput, lineWidth: 1.5)
                        }
                    }

                    KitchenTextField(
                        label: "Nota",
                        text: $noteText
                    )

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.warningText)
                            .padding(.horizontal, Spacing.xs)
                    }

                    Spacer(minLength: Spacing.lg)

                    Button("Guardar precio") {
                        Task {
                            await save()
                        }
                    }
                    .buttonStyle(.kitchenPrimary)
                    .disabled(parsedPriceCents == nil || isSaving)
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.xxl)
            }
            .background(.canvasBackground)
            .navigationTitle("Registrar precio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func save() async {
        guard let cents = parsedPriceCents else { return }
        isSaving = true
        errorMessage = nil

        let trimmedNote = noteText.trimmingCharacters(in: .whitespaces)
        let note = trimmedNote.isEmpty ? nil : trimmedNote

        let body = PriceRecordCreateRequest(
            priceCents: cents,
            recordedAt: recordedAt,
            note: note
        )

        do {
            let _: PriceRecord = try await NetworkService.shared.request(
                .post,
                "/presentations/\(presentationId)/prices",
                body: body
            )
            isSaving = false
            onSaved()
            dismiss()
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Previews

#if DEBUG
private let mockPresentationWithPrice = Presentation(
    id: "pres_1",
    ingredientId: "ing_1",
    ingredientName: "Harina de trigo",
    brand: "Selecta",
    supplierId: "sup_1",
    supplierName: "Walmart",
    packageQuantity: "1000",
    baseUnit: .g,
    barcode: nil,
    latestPriceCents: 2500,
    latestPriceAt: Date(),
    costPerBaseUnit: "2.500000",
    isCurrent: true,
    priceAgeDays: 0,
    priceIsStale: false,
    createdAt: Date(),
    updatedAt: Date()
)

private let mockPresentationStale = Presentation(
    id: "pres_2",
    ingredientId: "ing_1",
    ingredientName: "Harina de trigo",
    brand: "San Antonio",
    supplierId: "sup_1",
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
)

private let mockPresentationNoPrice = Presentation(
    id: "pres_3",
    ingredientId: "ing_1",
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

private let mockPricesHistory: [PriceRecord] = [
    PriceRecord(
        id: "pr_2",
        priceCents: 2500,
        recordedAt: Date(),
        note: "Comprada en oferta"
    ),
    PriceRecord(
        id: "pr_1",
        priceCents: 2350,
        recordedAt: Date().addingTimeInterval(-10 * 86400),
        note: nil
    )
]

#Preview("Con precio e historial - Claro") {
    NavigationStack {
        BrandDetailView(
            presentation: mockPresentationWithPrice,
            mockPrices: mockPricesHistory
        )
    }
}

#Preview("Precio viejo - Claro") {
    NavigationStack {
        BrandDetailView(
            presentation: mockPresentationStale,
            mockPrices: [mockPricesHistory[1]]
        )
    }
}

#Preview("Sin precio - Claro") {
    NavigationStack {
        BrandDetailView(
            presentation: mockPresentationNoPrice,
            mockPrices: []
        )
    }
}

#Preview("Letra AX3") {
    NavigationStack {
        BrandDetailView(
            presentation: mockPresentationWithPrice,
            mockPrices: mockPricesHistory
        )
    }
    .dynamicTypeSize(.accessibility3)
}
#endif
