import SwiftUI

/// Vista de Clientes según Bloque I7a.
struct CustomersView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var model: CustomersModel
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var showingNewCustomer = false
    @State private var customerToDelete: Customer?
    @State private var showingDeleteConfirmation = false

    init(model: CustomersModel = CustomersModel()) {
        self._model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            content
                .background(.canvasBackground)
                .navigationTitle("Clientes")
                .searchable(text: $searchText, prompt: "Buscar cliente")
                .onChange(of: searchText) { _, newValue in
                    searchTask?.cancel()
                    searchTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        if !Task.isCancelled {
                            await model.load(query: newValue)
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Listo") {
                            dismiss()
                        }
                        .font(.body.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        AddToolbarButton(label: "Nuevo cliente") {
                            showingNewCustomer = true
                        }
                    }
                }
                .sheet(isPresented: $showingNewCustomer) {
                    CustomerFormView(isMock: model.isMock) { created in
                        model.upsertCustomer(created)
                    }
                }
                .confirmationDialog(
                    "¿Borrar a \(customerToDelete?.name ?? "este cliente")?",
                    isPresented: $showingDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Borrar", role: .destructive) {
                        if let customer = customerToDelete {
                            Task {
                                await model.deleteCustomer(id: customer.id)
                            }
                        }
                    }
                    Button("Cancelar", role: .cancel) {
                        customerToDelete = nil
                    }
                } message: {
                    Text("Sus pedidos se conservan.")
                }
                .alert("Error", isPresented: Binding(
                    get: { model.actionErrorMessage != nil },
                    set: { if !$0 { model.actionErrorMessage = nil } }
                )) {
                    Button("Aceptar", role: .cancel) {
                        model.actionErrorMessage = nil
                    }
                } message: {
                    if let actionErrorMessage = model.actionErrorMessage {
                        Text(actionErrorMessage)
                    }
                }
                .task {
                    if model.state == .idle {
                        await model.load()
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading where model.customers.isEmpty:
            ProgressView()
                .tint(Color.accentColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message) where model.customers.isEmpty:
            ErrorStateView(message: message) {
                Task {
                    await model.load(query: searchText)
                }
            }
        default:
            if model.customers.isEmpty {
                ScrollView {
                    if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        ContentUnavailableView(
                            "Todavía no tienes clientes",
                            systemImage: "person.2",
                            description: Text("Agrégalos aquí o al crear un pedido.")
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .refreshable {
                    await model.load(query: searchText)
                }
            } else {
                List {
                    ForEach(model.customers) { customer in
                        NavigationLink {
                            CustomerDetailView(
                                customer: customer,
                                isMock: model.isMock,
                                onCustomerUpdated: { updated in
                                    model.upsertCustomer(updated)
                                },
                                onCustomerDeleted: { id in
                                    model.removeCustomer(id: id)
                                }
                            )
                        } label: {
                            customerRow(customer)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                customerToDelete = customer
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
                    await model.load(query: searchText)
                }
            }
        }
    }

    private func customerRow(_ customer: Customer) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(customer.name)
                .font(.body.weight(.semibold))
                .foregroundStyle(.inkPrimary)

            if let phone = customer.phone, !phone.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(phone)
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}

// MARK: - Previews

#if DEBUG
private let mockCustomersSample: [Customer] = [
    Customer(
        id: "mock_c1",
        name: "Ana Ruiz",
        phone: "55 1234 5678",
        notes: "Le gusta poco dulce, recoge en la tarde",
        createdAt: Date(),
        updatedAt: Date()
    ),
    Customer(
        id: "mock_c2",
        name: "Carlos Mendoza",
        phone: "81 9876 5432",
        notes: "Pizzería Bella Napoli. Entrega antes de la 1:00 pm",
        createdAt: Date(),
        updatedAt: Date()
    ),
    Customer(
        id: "mock_c3",
        name: "Doña Mary",
        phone: "33 2345 6789",
        notes: "Fonda El Buen Sabor. Salsa aparte, factura fin de mes",
        createdAt: Date(),
        updatedAt: Date()
    ),
    Customer(
        id: "mock_c4",
        name: "Roberto Garza",
        phone: nil,
        notes: "Cafetería La Selva",
        createdAt: Date(),
        updatedAt: Date()
    )
]

#Preview("Claro") {
    CustomersView(model: CustomersModel(mockCustomers: mockCustomersSample))
}

#Preview("Letra AX3") {
    CustomersView(model: CustomersModel(mockCustomers: mockCustomersSample))
        .dynamicTypeSize(.accessibility3)
}
#endif
