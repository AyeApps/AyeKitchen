import SwiftUI
import KitchenDomain

// MARK: - Selección de Tienda

enum SupplierSelection: Hashable, Sendable {
    case none
    case existing(id: String, name: String)

    var displayName: String {
        switch self {
        case .none: "Sin tienda"
        case .existing(_, let name): name
        }
    }

    var supplierId: String? {
        switch self {
        case .none: nil
        case .existing(let id, _): id
        }
    }
}

// MARK: - Componente StorePickerField

struct StorePickerField: View {
    @Binding var selection: SupplierSelection
    var store: LocalStore = .shared
    var onError: ((String?) -> Void)? = nil

    @State private var showingNewSupplierAlert = false
    @State private var newSupplierName = ""

    var suppliers: [Supplier] {
        store.data.activeSuppliers()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Tienda")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.inkPrimary)

            Menu {
                Button("Sin tienda") {
                    selection = .none
                }
                ForEach(suppliers) { supplier in
                    Button(supplier.name) {
                        selection = .existing(id: supplier.id, name: supplier.name)
                    }
                }
                Divider()
                Button("Nueva tienda…") {
                    newSupplierName = ""
                    showingNewSupplierAlert = true
                }
            } label: {
                HStack {
                    Text(selection.displayName)
                        .font(.body)
                        .foregroundStyle(.inkPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.inkMuted)
                }
                .padding(.horizontal, 18)
                .frame(minHeight: 56)
                .background(.surfaceInput, in: .rect(cornerRadius: Radius.card))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.card)
                        .strokeBorder(Color.borderInput, lineWidth: 1.5)
                }
            }
            .accessibilityLabel("Tienda: \(selection.displayName)")
        }
        .alert("Nueva tienda", isPresented: $showingNewSupplierAlert) {
            TextField("Nombre de la tienda", text: $newSupplierName)
            Button("Guardar") {
                createSupplier(name: newSupplierName)
                newSupplierName = ""
            }
            Button("Cancelar", role: .cancel) {
                newSupplierName = ""
            }
        }
    }

    private func createSupplier(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            let created = try store.mutate { data, ctx in
                try data.createSupplier(name: trimmed, ctx: ctx)
            }
            selection = .existing(id: created.id, name: created.name)
            onError?(nil)
        } catch let domainError as DomainError {
            onError?(domainError.detail)
        } catch {
            onError?(error.localizedDescription)
        }
    }
}

#if DEBUG
#Preview("StorePickerField") {
    struct PreviewWrapper: View {
        @State private var selection: SupplierSelection = .none
        var body: some View {
            StorePickerField(selection: $selection, store: .preview())
                .padding()
        }
    }
    return PreviewWrapper()
}
#endif
