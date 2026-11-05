import SwiftUI
import KitchenDomain

// MARK: - Vista de Detalle de Marca

/// Detalle de la marca con precio actual, tarjeta suave, registro de nuevo precio e historial.
struct BrandDetailView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let presentationId: String
    private let store: LocalStore
    @State private var model: BrandDetailModel
    @State private var showingEditSheet = false
    @State private var showingRecordPriceSheet = false

    init(presentationId: String, store: LocalStore = .shared) {
        self.presentationId = presentationId
        self.store = store
        self._model = State(initialValue: BrandDetailModel(
            presentationId: presentationId,
            store: store
        ))
    }

    var body: some View {
        Group {
            if let presentation = model.presentation {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.section) {
                        priceCard(for: presentation)
                        registerPriceButton
                        priceHistorySection
                    }
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, Spacing.xxl)
                }
                .navigationTitle(presentation.brand)
            } else {
                ContentUnavailableView("Marca no encontrada", systemImage: "questionmark.folder")
                    .navigationTitle("Marca")
            }
        }
        .background(.canvasBackground)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.presentation != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Editar") {
                        showingEditSheet = true
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            BrandFormView(mode: .edit(presentationId: presentationId), store: store)
        }
        .sheet(isPresented: $showingRecordPriceSheet) {
            RecordPriceSheet(presentationId: presentationId, store: store)
        }
    }

    // MARK: - Tarjeta de Precio

    private func priceCard(for presentation: CatalogPresentation) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let cents = presentation.latestPriceCents {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(Money.format(cents: cents))
                            .font(.title.weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(.inkPrimary)
                        if presentation.priceIsStale {
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
                        if presentation.priceIsStale {
                            Chip("Precio viejo", tone: .warning)
                        }
                    }
                }

                Text(packageStoreAndAgeText(for: presentation))
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
            } else {
                Text("Todavía no tiene precio.")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(.inkPrimary)

                Text(packageAndStoreText(for: presentation))
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
            }
        }
        .softCard()
    }

    private func packageStoreAndAgeText(for presentation: CatalogPresentation) -> String {
        var parts: [String] = []
        let pkg = "por \(Quantity.format(presentation.packageQuantity)) \(presentation.baseUnit.rawValue)"
        parts.append(pkg)

        if let store = presentation.supplierName, !store.isEmpty {
            parts.append(store)
        }

        if let age = ageDescription(days: presentation.priceAgeDays) {
            parts.append(age)
        }

        return parts.joined(separator: " · ")
    }

    private func packageAndStoreText(for presentation: CatalogPresentation) -> String {
        var parts: [String] = []
        let pkg = "por \(Quantity.format(presentation.packageQuantity)) \(presentation.baseUnit.rawValue)"
        parts.append(pkg)

        if let store = presentation.supplierName, !store.isEmpty {
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

            if model.prices.isEmpty {
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
    private let store: LocalStore
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model: RecordPriceModel

    init(presentationId: String, store: LocalStore = .shared, onSaved: @escaping () -> Void = {}) {
        self.presentationId = presentationId
        self.store = store
        self.onSaved = onSaved
        self._model = State(initialValue: RecordPriceModel(presentationId: presentationId, store: store))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    KitchenTextField(
                        label: "Precio",
                        text: $model.priceText,
                        keyboard: .decimalPad
                    )

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("¿Cuándo lo pagaste?")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.inkPrimary)

                        DatePicker(
                            "¿Cuándo lo pagaste?",
                            selection: $model.recordedAt,
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
                        text: $model.noteText
                    )

                    if let errorMessage = model.errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.warningText)
                            .padding(.horizontal, Spacing.xs)
                    }

                    Spacer(minLength: Spacing.lg)

                    Button("Guardar precio") {
                        if model.save() {
                            onSaved()
                            dismiss()
                        }
                    }
                    .buttonStyle(.kitchenPrimary)
                    .disabled(!model.canSave)
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
}

// MARK: - Previews

#if DEBUG
#Preview("Con precio e historial - Claro") {
    NavigationStack {
        BrandDetailView(presentationId: "pres-selecta", store: .preview())
    }
}

#Preview("Precio viejo - Claro") {
    NavigationStack {
        BrandDetailView(presentationId: "pres-tres", store: .preview())
    }
}

#Preview("Letra AX3") {
    NavigationStack {
        BrandDetailView(presentationId: "pres-selecta", store: .preview())
    }
    .dynamicTypeSize(.accessibility3)
}
#endif
