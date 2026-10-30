import SwiftUI

/// Hoja para buscar y seleccionar un cliente para el pedido según Bloque I7b.
struct CustomerPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var model: CustomersModel
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var showingNewCustomerSheet = false
    @State private var pendingCustomer: Customer?

    let onSelect: (Customer) -> Void

    init(
        model: CustomersModel = CustomersModel(),
        onSelect: @escaping (Customer) -> Void
    ) {
        _model = State(initialValue: model)
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            content
                .background(.canvasBackground)
                .navigationTitle("Cliente")
                .navigationBarTitleDisplayMode(.inline)
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
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") {
                            dismiss()
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                    }
                }
                .sheet(isPresented: $showingNewCustomerSheet, onDismiss: {
                    if let pending = pendingCustomer {
                        pendingCustomer = nil
                        onSelect(pending)
                        dismiss()
                    }
                }) {
                    CustomerFormView(
                        initialName: searchText.trimmingCharacters(in: .whitespaces),
                        isMock: model.isMock
                    ) { savedCustomer in
                        model.upsertCustomer(savedCustomer)
                        pendingCustomer = savedCustomer
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
        List {
            newCustomerButton
                .listRowBackground(Color.surfaceCard)

            if model.state == .loading && model.customers.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(Color.accentColor)
                    Spacer()
                }
                .padding(.vertical, Spacing.xl)
                .listRowBackground(Color.clear)
            } else if case .error(let message) = model.state, model.customers.isEmpty {
                ErrorStateView(message: message) {
                    Task {
                        await model.load(query: searchText)
                    }
                }
                .listRowBackground(Color.clear)
            } else if model.customers.isEmpty {
                emptyState
            } else {
                ForEach(model.customers) { customer in
                    customerRow(customer)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable {
            await model.load(query: searchText)
        }
    }

    private var newCustomerButton: some View {
        Button {
            showingNewCustomerSheet = true
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "plus.circle.fill")
                    .imageScale(.medium)
                Text(newCustomerButtonTitle)
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.accentColor)
        }
    }

    private var newCustomerButtonTitle: String {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return "Nuevo cliente"
        } else {
            return "Crear “\(trimmed)”"
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            Text("Todavía no tienes clientes.")
                .font(.subheadline)
                .foregroundStyle(.inkMuted)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, Spacing.xl)
                .listRowBackground(Color.clear)
        } else {
            Text("No se encontraron clientes.")
                .font(.subheadline)
                .foregroundStyle(.inkMuted)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, Spacing.xl)
                .listRowBackground(Color.clear)
        }
    }

    private func customerRow(_ customer: Customer) -> some View {
        Button {
            onSelect(customer)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(customer.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.inkPrimary)

                if let phone = customer.phone, !phone.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(phone)
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.surfaceCard)
    }
}

// MARK: - Previews

#if DEBUG
private let previewCustomers: [Customer] = [
    Customer(
        id: "c-1",
        name: "Mariana Rojas",
        phone: "5512345678",
        notes: nil,
        createdAt: Date.now,
        updatedAt: Date.now
    ),
    Customer(
        id: "c-2",
        name: "Carlos Benítez",
        phone: nil,
        notes: nil,
        createdAt: Date.now,
        updatedAt: Date.now
    )
]

#Preview("Selector de cliente — Con clientes") {
    CustomerPickerSheet(
        model: CustomersModel(mockCustomers: previewCustomers)
    ) { _ in }
}

#Preview("Selector de cliente — Letra AX3") {
    CustomerPickerSheet(
        model: CustomersModel(mockCustomers: previewCustomers)
    ) { _ in }
    .dynamicTypeSize(.accessibility3)
}

#Preview("Selector de cliente — Vacío") {
    CustomerPickerSheet(
        model: CustomersModel(mockCustomers: [])
    ) { _ in }
}
#endif
