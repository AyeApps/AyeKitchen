import Foundation
import Observation

/// ViewModel para la pantalla de detalle de cliente (`CustomerDetailView`).
@Observable final class CustomerDetailModel {
    var customer: Customer
    var orders: [Order] = []
    var isLoadingOrders: Bool = false
    var ordersErrorMessage: String? = nil
    private(set) var isMock: Bool = false

    init(customer: Customer, mockOrders: [Order]? = nil, isMock: Bool = false) {
        self.customer = customer
        if let mockOrders {
            self.orders = mockOrders
            self.isMock = true
        } else if isMock {
            self.isMock = true
        }
    }

    func updateCustomer(_ updated: Customer) {
        self.customer = updated
    }

    func loadOrders() async {
        guard !isMock else { return }
        isLoadingOrders = true
        ordersErrorMessage = nil
        do {
            let page: Page<Order> = try await NetworkService.shared.request(
                .get,
                "/orders/",
                query: [
                    URLQueryItem(name: "customer_id", value: customer.id),
                    URLQueryItem(name: "limit", value: "100")
                ]
            )
            self.orders = page.items
            self.isLoadingOrders = false
        } catch let apiError as APIError {
            self.isLoadingOrders = false
            self.ordersErrorMessage = apiError.localizedDescription
        } catch {
            self.isLoadingOrders = false
            self.ordersErrorMessage = error.localizedDescription
        }
    }
}
