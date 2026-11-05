import SwiftUI
import KitchenDomain

/// Hoja para buscar y seleccionar un cliente para el pedido (Bloque I18 local-first).
struct CustomerPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let store: LocalStore
    @State private var searchText = ""
    @State private var showingNewCustomerSheet = false

    let onSelect: (Customer) -> Void

    init(
        store: LocalStore = .shared,
        onSelect: @escaping (Customer) -> Void
    ) {
        self.store = store
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            content
                .background(.canvasBackground)
                .navigationTitle("Cliente")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $searchText, prompt: "Buscar cliente")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") {
                            dismiss()
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                    }
                }
                .sheet(isPresented: $showingNewCustomerSheet) {
                    CustomerFormView(
                        initialName: searchText.trimmingCharacters(in: .whitespaces),
                        store: store
                    ) { savedCustomer in
                        onSelect(savedCustomer)
                        dismiss()
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        let customers = store.data.listCustomers(query: searchText)
        List {
            newCustomerButton
                .listRowBackground(Color.surfaceCard)

            if customers.isEmpty {
                emptyState
            } else {
                ForEach(customers) { customer in
                    customerRow(customer)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
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
#Preview("Selector de cliente") {
    CustomerPickerSheet(store: .preview()) { _ in }
}

#Preview("Selector de cliente — AX3") {
    CustomerPickerSheet(store: .preview()) { _ in }
        .dynamicTypeSize(.accessibility3)
}
#endif
