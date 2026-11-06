import SwiftUI
import KitchenDomain

/// Vista de Clientes (Bloque I18 local-first).
struct CustomersView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var model: CustomersModel
    @State private var searchText = ""
    @State private var showingNewCustomer = false
    @State private var customerToDelete: Customer?
    @State private var showingDeleteConfirmation = false

    init(store: LocalStore = .shared) {
        self._model = State(initialValue: CustomersModel(store: store))
    }

    init(model: CustomersModel) {
        self._model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            content
                .background(.canvasBackground)
                .navigationTitle("Clientes")
                .searchable(text: $searchText, prompt: "Buscar cliente")
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
                    CustomerFormView(store: model.store)
                }
                .confirmationDialog(
                    "¿Borrar a \(customerToDelete?.name ?? "este cliente")?",
                    isPresented: $showingDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Borrar", role: .destructive) {
                        if let customer = customerToDelete {
                            model.deleteCustomer(id: customer.id)
                            customerToDelete = nil
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
        }
    }

    @ViewBuilder
    private var content: some View {
        let customers = model.customers(query: searchText)
        if customers.isEmpty {
            ScrollView {
                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ContentUnavailableView {
                        Label("Todavía no tienes clientes", systemImage: "person.2")
                    } description: {
                        Text("Agrégalos aquí o al crear un pedido.")
                    } actions: {
                        Button {
                            showingNewCustomer = true
                        } label: {
                            Text("Nuevo cliente")
                        }
                        .buttonStyle(.kitchenPrimary)
                        .padding(.horizontal, Spacing.xxl)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(customers) { customer in
                    NavigationLink {
                        CustomerDetailView(
                            customerId: customer.id,
                            store: model.store
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
#Preview("Claro") {
    CustomersView(store: .preview())
}

#Preview("Letra AX3") {
    CustomersView(store: .preview())
        .dynamicTypeSize(.accessibility3)
}
#endif
