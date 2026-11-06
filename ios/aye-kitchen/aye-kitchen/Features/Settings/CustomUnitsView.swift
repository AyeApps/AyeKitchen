import SwiftUI
import KitchenDomain

/// Lista de las unidades propias del negocio (Bloque I21).
struct CustomUnitsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let store: LocalStore

    @State private var showingCreateSheet = false
    @State private var unitToEdit: KitchenUnit?
    @State private var unitToDelete: KitchenUnit?
    @State private var showingDeleteConfirmation = false
    @State private var actionErrorMessage: String?

    init(store: LocalStore = .shared) {
        self.store = store
    }

    private var customUnits: [KitchenUnit] {
        store.data.units
            .filter { $0.isActive }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Group {
            if customUnits.isEmpty {
                emptyView
            } else {
                listView
            }
        }
        .background(.canvasBackground)
        .navigationTitle("Unidades propias")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AddToolbarButton(label: "Nueva unidad") {
                    showingCreateSheet = true
                }
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CustomUnitFormView(store: store)
        }
        .sheet(item: $unitToEdit) { unit in
            CustomUnitFormView(unit: unit, store: store)
        }
        .confirmationDialog(
            "¿Borrar unidad?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Borrar", role: .destructive) {
                if let unit = unitToDelete {
                    deleteUnit(unit)
                }
            }
            Button("Cancelar", role: .cancel) {
                unitToDelete = nil
            }
        } message: {
            if let unit = unitToDelete {
                Text("¿Seguro que quieres borrar \"\(unit.name)\"? Si está en uso en ingredientes o recetas no se podrá borrar.")
            }
        }
        .alert("No se pudo borrar", isPresented: Binding(
            get: { actionErrorMessage != nil },
            set: { if !$0 { actionErrorMessage = nil } }
        )) {
            Button("Aceptar", role: .cancel) {
                actionErrorMessage = nil
            }
        } message: {
            if let actionErrorMessage {
                Text(actionErrorMessage)
            }
        }
    }

    // MARK: - Estado vacío

    private var emptyView: some View {
        ScrollView {
            ContentUnavailableView(
                "Todavía no tienes unidades propias",
                systemImage: "scalemass",
                description: Text("Crea unidades para paquetes o medidas que uses en tu cocina.")
            )
            .padding(.top, Spacing.xxl)
        }
    }

    // MARK: - Lista de unidades

    private var listView: some View {
        List {
            ForEach(customUnits) { unit in
                Button {
                    unitToEdit = unit
                } label: {
                    unitRow(unit)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        unitToDelete = unit
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Borrar", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func unitRow(_ unit: KitchenUnit) -> some View {
        let factorFormatted = Quantity.format(unit.factorToBase)
        let formula = "1 \(unit.abbreviation) = \(factorFormatted) \(unit.baseUnit.rawValue)"

        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(unit.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.inkPrimary)
                    Text(unit.abbreviation)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.inkMuted)
                    Text(formula)
                        .font(.subheadline)
                        .foregroundStyle(.inkSecondary)
                }
            } else {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack {
                        Text(unit.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.inkPrimary)
                        Spacer()
                        Text(unit.abbreviation)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.inkMuted)
                    }
                    Text(formula)
                        .font(.subheadline)
                        .foregroundStyle(.inkSecondary)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Borrado

    private func deleteUnit(_ unit: KitchenUnit) {
        do {
            try store.mutate { data, ctx in
                try data.deleteUnit(id: unit.id, ctx: ctx)
            }
            unitToDelete = nil
        } catch let domainError as DomainError {
            switch domainError {
            case .inUse:
                actionErrorMessage = "Esta unidad está en uso en tus ingredientes o recetas. Quítala de ahí antes de borrarla."
            case .duplicateName:
                actionErrorMessage = "Ya existe una unidad con ese nombre o abreviatura."
            default:
                actionErrorMessage = domainError.detail
            }
            unitToDelete = nil
        } catch {
            actionErrorMessage = error.localizedDescription
            unitToDelete = nil
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Con unidades - Normal") {
    var data = KitchenData.previewSample
    data.units = [
        KitchenUnit(
            id: "unit-bolsa",
            name: "Bolsa chica",
            abbreviation: "bolsa",
            baseUnit: .g,
            factorToBase: "500",
            createdAt: Date(),
            updatedAt: Date()
        ),
        KitchenUnit(
            id: "unit-caja",
            name: "Caja de piezas",
            abbreviation: "caja",
            baseUnit: .pz,
            factorToBase: "12",
            createdAt: Date(),
            updatedAt: Date()
        ),
        KitchenUnit(
            id: "unit-frasco",
            name: "Frasco",
            abbreviation: "frasco",
            baseUnit: .ml,
            factorToBase: "250",
            createdAt: Date(),
            updatedAt: Date()
        ),
    ]
    return NavigationStack {
        CustomUnitsView(store: .preview(data))
    }
}

#Preview("Con unidades - Accesibilidad") {
    var data = KitchenData.previewSample
    data.units = [
        KitchenUnit(
            id: "unit-bolsa",
            name: "Bolsa chica",
            abbreviation: "bolsa",
            baseUnit: .g,
            factorToBase: "500",
            createdAt: Date(),
            updatedAt: Date()
        )
    ]
    return NavigationStack {
        CustomUnitsView(store: .preview(data))
    }
    .dynamicTypeSize(.accessibility3)
}

#Preview("Sin unidades - Normal") {
    NavigationStack {
        CustomUnitsView(store: .preview())
    }
}
#endif
