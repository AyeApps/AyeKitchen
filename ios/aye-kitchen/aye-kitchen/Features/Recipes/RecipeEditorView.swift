import SwiftUI
import TipKit
import KitchenDomain

/// Editor de receta (crear y editar) según Bloque I3b / I17 local-first.
struct RecipeEditorView: View {
    typealias Mode = RecipeEditorMode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var model: RecipeEditorModel
    private let store: LocalStore
    @State private var showingDiscardAlert = false
    @State private var showingItemPicker = false
    @State private var showingAddExtraCost = false
    @State private var showingFixedCostsHelp = false

    @State private var editingTarget: LineTarget?
    @State private var editingExistingLine: RecipeEditorLine?

    let onSave: (@MainActor @Sendable (Recipe) -> Void)?

    init(
        mode: RecipeEditorMode = .create,
        store: LocalStore = .shared,
        onSave: (@MainActor @Sendable (Recipe) -> Void)? = nil
    ) {
        self.store = store
        self._model = State(initialValue: RecipeEditorModel(mode: mode, store: store))
        self.onSave = onSave
    }

    init(
        _ mode: RecipeEditorMode = .create,
        store: LocalStore = .shared,
        onSave: (@MainActor @Sendable (Recipe) -> Void)? = nil
    ) {
        self.init(mode: mode, store: store, onSave: onSave)
    }

    init(
        recipeId: String?,
        store: LocalStore = .shared,
        onSave: (@MainActor @Sendable (Recipe) -> Void)? = nil
    ) {
        if let recipeId {
            self.init(mode: .edit(recipeId: recipeId), store: store, onSave: onSave)
        } else {
            self.init(mode: .create, store: store, onSave: onSave)
        }
    }

    var body: some View {
        NavigationStack {
            editorContent
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
                        editingRecipeId: {
                            if case .edit(let id) = model.mode { return id }
                            return nil
                        }(),
                        allUnits: model.allUnits,
                        store: store
                    ) { line in
                        model.addLine(line)
                    }
                }
                .sheet(isPresented: $showingAddExtraCost) {
                    AddExtraCostSheet { cost in
                        model.addExtraCost(cost)
                    }
                }
                .sheet(isPresented: $showingFixedCostsHelp) {
                    FixedCostsHelpSheet()
                }
                .sheet(item: $editingTarget) { target in
                    RecipeLineSheet(
                        target: target,
                        existingLine: editingExistingLine,
                        allUnits: model.allUnits,
                        store: store
                    ) { updatedLine in
                        model.updateLine(updatedLine)
                        editingTarget = nil
                        editingExistingLine = nil
                    }
                }
        }
    }

    private var editorContent: some View {
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

            TipView(RecipeYieldTip())
                .tipBackground(.surfaceCard)

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
                        Image(systemName: "fork.knife")
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
        if let target = model.loadTarget(for: item) {
            editingExistingLine = item
            editingTarget = target
        }
    }

    private var extraCostsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            extraCostsHeader

            TipView(RecipeFixedCostsTip())
                .tipBackground(.surfaceCard)

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

    @ViewBuilder
    private var extraCostsHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Costos fijos")
                    .sectionTitleStyle()

                Button {
                    showingFixedCostsHelp = true
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "questionmark.circle")
                        Text("¿Qué es esto?")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
            }
        } else {
            HStack {
                Text("Costos fijos")
                    .sectionTitleStyle()

                Spacer()

                Button {
                    showingFixedCostsHelp = true
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "questionmark.circle")
                        Text("¿Qué es esto?")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
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
            do {
                let saved = try model.save()
                onSave?(saved)
                dismiss()
            } catch {
                model.errorMessage = userFacingRecipeError(error)
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

#if DEBUG
#Preview("Nueva Receta") {
    let previewStore = LocalStore.preview()
    RecipeEditorView(mode: .create, store: previewStore) { _ in }
}

#Preview("Editar Receta — Pastel de vainilla") {
    let previewStore = LocalStore.preview()
    RecipeEditorView(mode: .edit(recipeId: "rec-pastel"), store: previewStore) { _ in }
}

#Preview("Editar Receta — Accesibilidad AX3") {
    let previewStore = LocalStore.preview()
    RecipeEditorView(mode: .edit(recipeId: "rec-pastel"), store: previewStore) { _ in }
        .dynamicTypeSize(.accessibility3)
}
#endif
