import SwiftUI

// MARK: - Cuerpos de petición (docs/api-contract.md)

nonisolated struct SupplierCreateRequest: Encodable, Sendable {
    let name: String
    let notes: String?
}

nonisolated struct SupplierUpdateRequest: Encodable, Sendable {
    let name: String
    let notes: String?
}

// MARK: - Modelo de Tiendas

@Observable final class SuppliersModel: @unchecked Sendable {
    var suppliers: [Supplier] = []
    var isLoading = false
    var errorMessage: String?

    init(mockSuppliers: [Supplier]? = nil) {
        if let mockSuppliers {
            self.suppliers = mockSuppliers
        }
    }

    func loadSuppliers() async {
        isLoading = true
        errorMessage = nil
        do {
            let list: [Supplier] = try await NetworkService.shared.request(.get, "/suppliers/")
            self.suppliers = list
            self.isLoading = false
        } catch {
            self.isLoading = false
            self.errorMessage = error.localizedDescription
        }
    }

    func createSupplier(name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        errorMessage = nil
        do {
            let body = SupplierCreateRequest(name: trimmed, notes: nil)
            let created: Supplier = try await NetworkService.shared.request(.post, "/suppliers/", body: body)
            suppliers.append(created)
            suppliers.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func renameSupplier(id: String, name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        errorMessage = nil
        do {
            let body = SupplierUpdateRequest(name: trimmed, notes: nil)
            let updated: Supplier = try await NetworkService.shared.request(.patch, "/suppliers/\(id)", body: body)
            if let index = suppliers.firstIndex(where: { $0.id == id }) {
                suppliers[index] = updated
                suppliers.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSupplier(id: String) async {
        errorMessage = nil
        do {
            try await NetworkService.shared.requestNoContent(.delete, "/suppliers/\(id)")
            suppliers.removeAll { $0.id == id }
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
                        Task {
                            await model.createSupplier(name: newSupplierName)
                        }
                    }
                    Button("Cancelar", role: .cancel) {
                        newSupplierName = ""
                    }
                }
                .alert("Renombrar tienda", isPresented: $showingRenameAlert) {
                    TextField("Nombre de la tienda", text: $renameSupplierName)
                    Button("Guardar") {
                        if let supplier = supplierToRename {
                            Task {
                                await model.renameSupplier(id: supplier.id, name: renameSupplierName)
                            }
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
                            Task {
                                await model.deleteSupplier(id: supplier.id)
                            }
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
                .task {
                    if model.suppliers.isEmpty {
                        await model.loadSuppliers()
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.suppliers.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.suppliers.isEmpty {
            ContentUnavailableView(
                "Todavía no tienes tiendas",
                systemImage: "storefront",
                description: Text("Agrega dónde compras: Walmart, Costco, el mercado…")
            )
            .refreshable {
                await model.loadSuppliers()
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
            .refreshable {
                await model.loadSuppliers()
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
private let mockSuppliersData: [Supplier] = [
    Supplier(
        id: "sup_1",
        name: "Costco",
        notes: nil,
        createdAt: Date(),
        updatedAt: Date()
    ),
    Supplier(
        id: "sup_2",
        name: "Mercado Central",
        notes: nil,
        createdAt: Date(),
        updatedAt: Date()
    ),
    Supplier(
        id: "sup_3",
        name: "Walmart",
        notes: nil,
        createdAt: Date(),
        updatedAt: Date()
    )
]

#Preview("Claro") {
    SuppliersView(model: SuppliersModel(mockSuppliers: mockSuppliersData))
}

#Preview("Letra AX3") {
    SuppliersView(model: SuppliersModel(mockSuppliers: mockSuppliersData))
        .dynamicTypeSize(.accessibility3)
}
#endif
