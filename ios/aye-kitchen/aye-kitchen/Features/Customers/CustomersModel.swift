import Foundation
import KitchenDomain
import Observation

/// ViewModel para la lista de clientes (MVVM, Regla 5 / Bloque I18 local-first).
@Observable
final class CustomersModel {
    var store: LocalStore
    var actionErrorMessage: String? = nil

    init(store: LocalStore = .shared) {
        self.store = store
    }

    func customers(query: String = "") -> [Customer] {
        store.data.listCustomers(query: query.isEmpty ? nil : query)
    }

    func deleteCustomer(id: String) {
        do {
            actionErrorMessage = nil
            try store.mutate { data, ctx in
                try data.deleteCustomer(id: id, ctx: ctx)
            }
        } catch let error as DomainError {
            actionErrorMessage = error.detail
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }
}
