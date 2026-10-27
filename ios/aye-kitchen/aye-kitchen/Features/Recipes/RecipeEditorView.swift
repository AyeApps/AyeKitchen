import SwiftUI

/// Editor de receta (crear y editar) según Bloque I3b.
struct RecipeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var model: RecipeEditorModel
    @State private var showingDiscardAlert = false
    @State private var showingItemPicker = false
    @State private var showingAddExtraCost = false

    @State private var editingTarget: LineTarget?
    @State private var editingExistingLine: RecipeEditorLine?
    @State private var isLoadingLineToEdit = false

    let onSave: @MainActor @Sendable (Recipe) -> Void

    init(
        recipe: Recipe? = nil,
        mockUnits: [MeasureUnit]? = nil,
        onSave: @escaping @MainActor @Sendable (Recipe) -> Void
    ) {
        _model = State(initialValue: RecipeEditorModel(recipe: recipe, mockUnits: mockUnits))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    nameAndDescriptionSection
                    yieldSection
                    ingredientsSection
                    extraCostsSection

                    if let errorMessage = model.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.warningText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Spacing.md)
                            .background(.warningSoft, in: .rect(cornerRadius: Radius.control))
                    }

                    saveButton
                }
                .padding(Spacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(.canvasBackground)
            .navigationTitle(model.isEditing ? "Editar receta" : "Nueva receta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        if model.hasUnsavedChanges {
                            showingDiscardAlert = true
                        } else {
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
                }
            }
            .confirmationDialog(
                "¿Descartar los cambios?",
                isPresented: $showingDiscardAlert,
                titleVisibility: .visible
            ) {
                Button("Descartar cambios", role: .destructive) {
                    dismiss()
                }
                Button("Seguir editando", role: .cancel) {}
            } message: {
                Text("Si sales ahora, los cambios que hiciste no se guardarán.")
            }
            .sheet(isPresented: $showingItemPicker) {
                RecipeItemPicker(
                    editingRecipeId: model.recipe?.id,
                    allUnits: model.allUnits
                ) { line in
                    model.addLine(line)
                }
            }
            .sheet(isPresented: $showingAddExtraCost) {
                AddExtraCostSheet { cost in
                    model.addExtraCost(cost)
                }
            }
            .sheet(item: $editingTarget) { target in
                RecipeLineSheet(
                    target: target,
                    existingLine: editingExistingLine,
                    allUnits: model.allUnits
                ) { updatedLine in
                    model.updateLine(updatedLine)
                    editingTarget = nil
                    editingExistingLine = nil
                }
            }
            .task {
                await model.loadInitialData()
            }
        }
    }

    // MARK: - Secciones

    private var nameAndDescriptionSection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            KitchenTextField(
                label: "Nombre",
                text: $model.name
            )

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Descripción")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.inkPrimary)

                TextField("", text: $model.descriptionText, axis: .vertical)
                    .lineLimit(3...5)
                    .font(.body)
                    .foregroundStyle(.inkPrimary)
                    .padding(14)
                    .background(.surfaceInput, in: .rect(cornerRadius: Radius.card))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.card)
                            .strokeBorder(Color.borderInput, lineWidth: 1.5)
                    }
            }
        }
    }

    private var yieldSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("¿Cuánto rinde?")
                .sectionTitleStyle()

            HStack(spacing: Spacing.md) {
                TextField("", text: $model.yieldQuantity)
                    .keyboardType(.decimalPad)
                    .font(.body.weight(.heavy).monospacedDigit())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.inkPrimary)
                    .frame(width: 80, height: 52)
                    .background(.surfaceInput, in: .rect(cornerRadius: Radius.card))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.card)
                            .strokeBorder(Color.borderInput, lineWidth: 1.5)
                    }
                    .accessibilityLabel("Cantidad de rendimiento")

                if dynamicTypeSize.isAccessibilitySize {
                    Picker("Unidad de rendimiento", selection: $model.yieldUnit) {
                        Text("Piezas").tag(BaseUnit.pz)
                        Text("Gramos").tag(BaseUnit.g)
                        Text("Mililitros").tag(BaseUnit.ml)
                    }
                    .pickerStyle(.menu)
                    .font(.body.weight(.bold))
                    .tint(Color.accentColor)
                } else {
                    Picker("Unidad de rendimiento", selection: $model.yieldUnit) {
                        Text("Piezas").tag(BaseUnit.pz)
                        Text("Gramos").tag(BaseUnit.g)
                        Text("Mililitros").tag(BaseUnit.ml)
                    }
                    .pickerStyle(.segmented)
                }
            }

            servingsRow
        }
    }

    private var servingsRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Porciones")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.inkPrimary)

                if let s = model.servings {
                    Text("\(s) \(s == 1 ? "porción" : "porciones")")
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                } else {
                    Text("Sin porciones")
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)
                }
            }

            Spacer()

            Stepper(
                "",
                onIncrement: {
                    if let s = model.servings {
                        model.servings = s + 1
                    } else {
                        model.servings = 1
                    }
                },
                onDecrement: {
                    if let s = model.servings {
                        if s <= 1 {
                            model.servings = nil
                        } else {
                            model.servings = s - 1
                        }
                    }
                }
            )
            .labelsHidden()
        }
        .padding(.vertical, Spacing.xs)
    }

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Ingredientes")
                .sectionTitleStyle()

            if !model.items.isEmpty {
                RowGroup {
                    ForEach(model.items) { item in
                        ingredientRow(item)
                    }
                }
            }

            Button {
                showingItemPicker = true
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "plus")
                    Text("Agregar ingrediente")
                }
                .font(.body.weight(.bold))
                .foregroundStyle(.tint)
                .frame(minHeight: 44)
            }
        }
    }

    private func ingredientRow(_ item: RecipeEditorLine) -> some View {
        HStack(spacing: Spacing.sm) {
            Button {
                model.removeLine(item)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.warningText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quitar \(item.refName)")

            Button {
                openLineForEditing(item)
            } label: {
                HStack(spacing: Spacing.sm) {
                    if item.kind == .recipe {
                        Image(systemName: "birthday.cake")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.accentTextDeep)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.refName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.inkPrimary)
                            .lineLimit(2)

                        HStack(spacing: Spacing.xs) {
                            Text(formatQuantityAndUnit(quantity: item.quantity, unitName: item.unitName))
                                .font(.subheadline)
                                .foregroundStyle(.inkMuted)

                            if let brand = item.pinnedBrandName, !brand.isEmpty {
                                Text("·")
                                    .font(.subheadline)
                                    .foregroundStyle(.inkMuted)
                                Text("Marca: \(brand)")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.tint)
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.inkMuted)
                }
                .padding(.vertical, Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.sm)
    }

    private func openLineForEditing(_ item: RecipeEditorLine) {
        Task {
            isLoadingLineToEdit = true
            defer { isLoadingLineToEdit = false }

            if item.kind == .ingredient {
                do {
                    let ing: Ingredient = try await NetworkService.shared.request(
                        .get,
                        "/ingredients/\(item.refId)"
                    )
                    editingExistingLine = item
                    editingTarget = .ingredient(ing)
                } catch {
                    // Fallback con datos locales si la red falla
                    let fallbackIng = Ingredient(
                        id: item.refId,
                        name: item.refName,
                        baseUnit: .g,
                        group: nil,
                        notes: nil,
                        conversions: [],
                        createdAt: .now,
                        updatedAt: .now
                    )
                    editingExistingLine = item
                    editingTarget = .ingredient(fallbackIng)
                }
            } else {
                do {
                    let rec: Recipe = try await NetworkService.shared.request(
                        .get,
                        "/recipes/\(item.refId)"
                    )
                    editingExistingLine = item
                    editingTarget = .subrecipe(id: rec.id, name: rec.name, yieldUnit: rec.yieldUnit)
                } catch {
                    editingExistingLine = item
                    editingTarget = .subrecipe(id: item.refId, name: item.refName, yieldUnit: .pz)
                }
            }
        }
    }

    private var extraCostsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Costos fijos")
                .sectionTitleStyle()

            if !model.extraCosts.isEmpty {
                RowGroup {
                    ForEach(model.extraCosts, id: \.self) { cost in
                        extraCostRow(cost)
                    }
                }
            }

            Button {
                showingAddExtraCost = true
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "plus")
                    Text("Agregar costo fijo")
                }
                .font(.body.weight(.bold))
                .foregroundStyle(.tint)
                .frame(minHeight: 44)
            }
        }
    }

    private func extraCostRow(_ cost: ExtraCost) -> some View {
        HStack(spacing: Spacing.sm) {
            Button {
                model.removeExtraCost(cost)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.warningText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quitar \(cost.name)")

            Text(cost.name)
                .font(.body.weight(.semibold))
                .foregroundStyle(.inkPrimary)

            Spacer()

            Text(Money.format(cents: cost.costCents))
                .font(.body.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.inkPrimary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.md)
    }

    private var saveButton: some View {
        Button {
            Task {
                do {
                    let saved = try await model.save()
                    onSave(saved)
                    dismiss()
                } catch {
                    model.errorMessage = userFacingRecipeError(error)
                }
            }
        } label: {
            if model.isSaving {
                ProgressView()
                    .tint(.accentInk)
            } else {
                Text("Guardar receta")
            }
        }
        .buttonStyle(.kitchenPrimary)
        .disabled(!model.canSave)
        .padding(.top, Spacing.sm)
    }
}

// MARK: - Previews

#Preview("Nueva Receta") {
    let mockUnits = [
        MeasureUnit(id: "u_g", name: "gramo", abbreviation: "g", baseUnit: .g, factorToBase: "1", isSystem: true),
        MeasureUnit(id: "u_kg", name: "kilogramo", abbreviation: "kg", baseUnit: .g, factorToBase: "1000", isSystem: true),
        MeasureUnit(id: "u_pz", name: "pieza", abbreviation: "pz", baseUnit: .pz, factorToBase: "1", isSystem: true)
    ]
    RecipeEditorView(mockUnits: mockUnits) { _ in }
}

#Preview("Editar Receta - Contrato") {
    RecipeEditorView(recipe: .mockContractExample) { _ in }
}

#Preview("Editar Receta - Accesibilidad AX3") {
    RecipeEditorView(recipe: .mockContractExample) { _ in }
        .dynamicTypeSize(.accessibility3)
}
