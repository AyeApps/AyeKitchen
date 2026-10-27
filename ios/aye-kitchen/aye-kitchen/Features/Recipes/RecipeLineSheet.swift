import SwiftUI

/// Hoja de línea según el artboard "Agregar ingrediente — iPhone".
/// Permite capturar cantidad, unidad, pregunta de equivalencia si aplica, y marca/precio.
struct RecipeLineSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var model: RecipeLineModel
    let onSave: @MainActor @Sendable (RecipeEditorLine) -> Void

    @ScaledMetric(relativeTo: .title2) private var stepperHeight: CGFloat = 56

    init(
        target: LineTarget,
        existingLine: RecipeEditorLine? = nil,
        allUnits: [MeasureUnit],
        mockPresentations: [Presentation]? = nil,
        onSave: @escaping @MainActor @Sendable (RecipeEditorLine) -> Void
    ) {
        _model = State(initialValue: RecipeLineModel(
            target: target,
            existingLine: existingLine,
            allUnits: allUnits,
            mockPresentations: mockPresentations
        ))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    titleSection
                    stepperSection
                    unitSection

                    if !model.isUnitConvertible {
                        equivalenceCard
                    }

                    if case .ingredient = model.target {
                        priceSection
                    }

                    summaryAndActionSection
                }
                .padding(Spacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(.canvasBackground)
            .navigationTitle(model.target.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
                }
            }
            .task {
                await model.loadPresentations()
            }
        }
    }

    // MARK: - Secciones

    private var titleSection: some View {
        Text("¿Cuánta \(model.target.name.lowercased()) lleva?")
            .font(.title2.weight(.heavy))
            .foregroundStyle(.inkPrimary)
    }

    private var stepperSection: some View {
        HStack(spacing: Spacing.md) {
            Button {
                model.decrementQuantity()
            } label: {
                Image(systemName: "minus")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.inkPrimary)
                    .frame(width: stepperHeight, height: stepperHeight)
                    .background(.surfaceCard, in: .rect(cornerRadius: Radius.primaryButton))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.primaryButton)
                            .strokeBorder(.borderInput, lineWidth: 1.5)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Restar cantidad")

            TextField("", text: $model.quantityText)
                .keyboardType(.decimalPad)
                .font(.title2.weight(.heavy).monospacedDigit())
                .multilineTextAlignment(.center)
                .foregroundStyle(.inkPrimary)
                .frame(height: stepperHeight)
                .background(.surfaceInput, in: .rect(cornerRadius: Radius.primaryButton))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.primaryButton)
                        .strokeBorder(.borderInput, lineWidth: 1.5)
                }
                .accessibilityLabel("Cantidad")

            Button {
                model.incrementQuantity()
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.inkPrimary)
                    .frame(width: stepperHeight, height: stepperHeight)
                    .background(.surfaceCard, in: .rect(cornerRadius: Radius.primaryButton))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.primaryButton)
                            .strokeBorder(.borderInput, lineWidth: 1.5)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sumar cantidad")
        }
    }

    @ViewBuilder
    private var unitSection: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Picker("Unidad: \(model.selectedUnit.map(unitDisplayLabel) ?? "")", selection: $model.selectedUnitId) {
                ForEach(model.availableUnits) { unit in
                    Text(unitDisplayLabel(for: unit)).tag(unit.id)
                }
            }
            .pickerStyle(.menu)
            .font(.body.weight(.bold))
            .tint(Color.accentColor)
            .accessibilityLabel("Unidad: \(model.selectedUnit.map(unitDisplayLabel) ?? "")")
        } else {
            HStack(spacing: Spacing.sm) {
                Picker("Unidad", selection: $model.selectedUnitId) {
                    ForEach(model.primaryUnits) { unit in
                        Text(unitDisplayLabel(for: unit)).tag(unit.id)
                    }
                }
                .pickerStyle(.segmented)

                if !model.moreUnits.isEmpty {
                    Menu {
                        ForEach(model.moreUnits) { unit in
                            Button(unitDisplayLabel(for: unit)) {
                                model.selectedUnitId = unit.id
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(model.isUnitInMore ? (model.selectedUnit.map(unitDisplayLabel) ?? "Más") : "Más")
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(model.isUnitInMore ? Color.accentInk : Color.accentColor)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(model.isUnitInMore ? .accentFill : .accentSoft, in: .capsule)
                    }
                }
            }
        }
    }

    private var equivalenceCard: some View {
        let basePlural: String = switch model.target.baseUnit {
        case .g: "gramos"
        case .ml: "mililitros"
        case .pz: "piezas"
        }
        let unitName = model.selectedUnit.map(unitDisplayLabel) ?? "unidad"

        return HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: "info.circle")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(equivalenceQuestionText(
                    ingredientName: model.target.name,
                    baseUnit: model.target.baseUnit,
                    unitName: unitName
                ))
                .font(.subheadline)
                .foregroundStyle(.inkPrimary)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Spacing.sm) {
                    Text("1 \(unitName) =")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.inkPrimary)

                    TextField("", text: $model.equivalenceQuantity)
                        .keyboardType(.decimalPad)
                        .font(.body.weight(.bold).monospacedDigit())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.inkPrimary)
                        .padding(.horizontal, Spacing.sm)
                        .frame(width: 90, height: 44)
                        .background(.surfaceInput, in: .rect(cornerRadius: Radius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.control)
                                .strokeBorder(Color.accentColor, lineWidth: 1.5)
                        }
                        .accessibilityLabel("Equivalencia en \(basePlural)")

                    Text(basePlural)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.inkPrimary)
                }
            }
        }
        .softCard()
    }

    private var priceSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Precio que usamos")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.inkPrimary)

            if model.isLoadingPresentations {
                ProgressView()
                    .tint(Color.accentColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Spacing.sm)
            } else if model.presentations.isEmpty {
                Text("Todavía no tiene precio. Agrégalo en Catálogo.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.warningText)
                    .padding(.vertical, Spacing.xs)
            } else if let presentation = model.currentOrPinnedPresentation {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.presentationTitle(presentation))
                            .font(.body.weight(.bold))
                            .foregroundStyle(.inkPrimary)

                        Text(model.presentationSubtitle(presentation))
                            .font(.subheadline)
                            .foregroundStyle(.inkMuted)
                    }

                    Spacer()

                    Menu("Cambiar") {
                        Button("Usar siempre el más reciente") {
                            model.pinnedPresentationId = nil
                        }

                        ForEach(model.presentations) { p in
                            let priceText = p.latestPriceCents != nil ? Money.format(cents: p.latestPriceCents!) : "sin precio"
                            Button("\(p.brand) (\(priceText))") {
                                model.pinnedPresentationId = p.id
                            }
                        }
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.tint)
                }
                .padding(Spacing.md)
                .background(.surfaceCard, in: .rect(cornerRadius: Radius.card))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.card)
                        .strokeBorder(.borderLine, lineWidth: 1)
                }
            }
        }
    }

    private var summaryAndActionSection: some View {
        VStack(spacing: Spacing.lg) {
            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.warningText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.md)
                    .background(.warningSoft, in: .rect(cornerRadius: Radius.control))
            }

            HStack(alignment: .firstTextBaseline) {
                Text(model.conversionSummaryText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.inkMuted)

                Spacer()

                if let cost = model.estimatedCostText {
                    Text(cost)
                        .font(.title3.weight(.heavy))
                        .monospacedDigit()
                        .foregroundStyle(.inkPrimary)
                }
            }

            Button {
                Task {
                    do {
                        let line = try await model.saveLine()
                        onSave(line)
                        dismiss()
                    } catch {
                        model.errorMessage = userFacingRecipeError(error)
                    }
                }
            } label: {
                if model.isSavingEquivalence {
                    ProgressView()
                        .tint(.accentInk)
                } else {
                    Text(model.existingLine != nil ? "Guardar cambios" : "Agregar a la receta")
                }
            }
            .buttonStyle(.kitchenPrimary)
            .disabled(!model.canSave)
        }
        .padding(.top, Spacing.sm)
    }
}

// MARK: - Previews

#Preview("Harina con Pregunta de Equivalencia") {
    let mockHarina = Ingredient(
        id: "ing-harina-preview",
        name: "Harina",
        baseUnit: .g,
        group: "Secos",
        notes: nil,
        conversions: [],
        createdAt: .now,
        updatedAt: .now
    )
    let mockUnits = [
        MeasureUnit(id: "u_g", name: "gramo", abbreviation: "g", baseUnit: .g, factorToBase: "1", isSystem: true),
        MeasureUnit(id: "u_kg", name: "kilogramo", abbreviation: "kg", baseUnit: .g, factorToBase: "1000", isSystem: true),
        MeasureUnit(id: "u_tz", name: "taza", abbreviation: "tz", baseUnit: .ml, factorToBase: "240", isSystem: true),
        MeasureUnit(id: "u_cda", name: "cucharada", abbreviation: "cda", baseUnit: .ml, factorToBase: "15", isSystem: true),
        MeasureUnit(id: "u_cdta", name: "cucharadita", abbreviation: "cdta", baseUnit: .ml, factorToBase: "5", isSystem: true)
    ]
    let mockPresentations = [
        Presentation(
            id: "p_1",
            ingredientId: "ing-harina-preview",
            ingredientName: "Harina",
            brand: "Selecta",
            supplierId: "s_1",
            supplierName: "Walmart",
            packageQuantity: "1000",
            baseUnit: .g,
            barcode: nil,
            latestPriceCents: 2350,
            latestPriceAt: .now,
            costPerBaseUnit: "2.350000",
            isCurrent: true,
            priceAgeDays: 0,
            priceIsStale: false,
            createdAt: .now,
            updatedAt: .now
        )
    ]

    RecipeLineSheet(
        target: .ingredient(mockHarina),
        allUnits: mockUnits,
        mockPresentations: mockPresentations
    ) { _ in }
}

#Preview("Harina - Accesibilidad AX3") {
    let mockHarina = Ingredient(
        id: "ing-harina-preview-ax",
        name: "Harina",
        baseUnit: .g,
        group: "Secos",
        notes: nil,
        conversions: [],
        createdAt: .now,
        updatedAt: .now
    )
    let mockUnits = [
        MeasureUnit(id: "u_g", name: "gramo", abbreviation: "g", baseUnit: .g, factorToBase: "1", isSystem: true),
        MeasureUnit(id: "u_kg", name: "kilogramo", abbreviation: "kg", baseUnit: .g, factorToBase: "1000", isSystem: true),
        MeasureUnit(id: "u_tz", name: "taza", abbreviation: "tz", baseUnit: .ml, factorToBase: "240", isSystem: true)
    ]

    RecipeLineSheet(
        target: .ingredient(mockHarina),
        allUnits: mockUnits
    ) { _ in }
    .dynamicTypeSize(.accessibility3)
}
