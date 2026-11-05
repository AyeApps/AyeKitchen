import Foundation
import KitchenDomain
import Observation

/// ViewModel para la pantalla de detalle de cliente (`CustomerDetailView`, Bloque I18 local-first).
@Observable
final class CustomerDetailModel {
    let customerId: String
    var store: LocalStore

    init(customerId: String, store: LocalStore = .shared) {
        self.customerId = customerId
        self.store = store
    }

    var customer: Customer? {
        try? store.data.customer(id: customerId)
    }

    var orders: [Order] {
        store.data.listOrders(customerId: customerId)
    }
}
