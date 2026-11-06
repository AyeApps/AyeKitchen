import SwiftUI
import KitchenDomain

// MARK: - Modelo de Tiendas

@Observable final class SuppliersModel {
    private let store: LocalStore
    var errorMessage: String?

    init(store: LocalStore = .shared) {
        self.store = store
    }

    var suppliers: [Supplier] {
        store.data.activeSuppliers()
    }

    func createSupplier(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        errorMessage = nil
        do {
            try store.mutate { data, ctx in
                try data.createSupplier(name: trimmed, ctx: ctx)
            }
        } catch let domainError as DomainError {
            errorMessage = domainError.detail
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func renameSupplier(id: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        errorMessage = nil
        do {
            try store.mutate { data, ctx in
                try data.updateSupplier(id: id, name: trimmed, ctx: ctx)
            }
        } catch let domainError as DomainError {
            errorMessage = domainError.detail
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSupplier(id: String) {
        errorMessage = nil
        do {
            try store.mutate { data, ctx in
                try data.deleteSupplier(id: id, ctx: ctx)
            }
        } catch let domainError as DomainError {
            errorMessage = domainError.detail
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Vista de Tiendas

/// Lista de tiendas (proveedores) con búsqueda local, creación, edición y borrado.
struct SuppliersView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var model: SuppliersModel
    @State private var searchText = ""
    @State private var showingAddAlert = false
    @State private var newSupplierName = ""
    @State private var supplierToRename: Supplier?
    @State private var showingRenameAlert = false
    @State private var renameSupplierName = ""
    @State private var supplierToDelete: Supplier?
    @State private var showingDeleteConfirmation = false

    init(model: SuppliersModel = SuppliersModel()) {
        self._model = State(initialValue: model)
    }

    init(store: LocalStore) {
        self._model = State(initialValue: SuppliersModel(store: store))
    }

    var filteredSuppliers: [Supplier] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return model.suppliers
        }
        return model.suppliers.filter {
            $0.name.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            content
                .background(.canvasBackground)
                .navigationTitle("Tiendas")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $searchText, prompt: "Buscar tienda")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Listo") {
                            dismiss()
                        }
                        .font(.body.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        AddToolbarButton(label: "Agregar tienda") {
                            newSupplierName = ""
                            showingAddAlert = true
                        }
                    }
                }
                .alert("Nueva tienda", isPresented: $showingAddAlert) {
                    TextField("Nombre de la tienda", text: $newSupplierName)
                    Button("Guardar") {
                        model.createSupplier(name: newSupplierName)
                        newSupplierName = ""
                    }
                    Button("Cancelar", role: .cancel) {
                        newSupplierName = ""
                    }
                }
                .alert("Renombrar tienda", isPresented: $showingRenameAlert) {
                    TextField("Nombre de la tienda", text: $renameSupplierName)
                    Button("Guardar") {
                        if let supplier = supplierToRename {
                            model.renameSupplier(id: supplier.id, name: renameSupplierName)
                        }
                    }
                    Button("Cancelar", role: .cancel) {
                        supplierToRename = nil
                    }
                }
                .confirmationDialog(
                    "¿Borrar \(supplierToDelete?.name ?? "esta tienda")?",
                    isPresented: $showingDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Borrar", role: .destructive) {
                        if let supplier = supplierToDelete {
                            model.deleteSupplier(id: supplier.id)
                        }
                    }
                    Button("Cancelar", role: .cancel) {
                        supplierToDelete = nil
                    }
                } message: {
                    Text("Las marcas de esta tienda se quedan sin tienda.")
                }
                .alert("Error", isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )) {
                    Button("Aceptar", role: .cancel) {
                        model.errorMessage = nil
                    }
                } message: {
                    if let errorMessage = model.errorMessage {
                        Text(errorMessage)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.suppliers.isEmpty {
            ContentUnavailableView {
                Label("Todavía no tienes tiendas", systemImage: "storefront")
            } description: {
                Text("Agrega dónde compras: Walmart, Costco, el mercado…")
            } actions: {
                Button {
                    newSupplierName = ""
                    showingAddAlert = true
                } label: {
                    Text("Agregar tienda")
                }
                .buttonStyle(.kitchenPrimary)
                .padding(.horizontal, Spacing.xxl)
            }
        } else if filteredSuppliers.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            List {
                ForEach(filteredSuppliers) { supplier in
                    Button {
                        supplierToRename = supplier
                        renameSupplierName = supplier.name
                        showingRenameAlert = true
                    } label: {
                        Text(supplier.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.inkPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, Spacing.xs)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            supplierToDelete = supplier
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Borrar", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Claro") {
    SuppliersView(store: .preview())
}

#Preview("Letra AX3") {
    SuppliersView(store: .preview())
        .dynamicTypeSize(.accessibility3)
}
#endif
