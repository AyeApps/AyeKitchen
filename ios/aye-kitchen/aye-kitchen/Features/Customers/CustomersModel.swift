import Foundation
import Observation

enum CustomersLoadingState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case error(String)
}

@Observable final class CustomersModel {
    var customers: [Customer] = []
    var state: CustomersLoadingState = .idle
    var actionErrorMessage: String? = nil
    private(set) var isMock: Bool = false
    private var allMockCustomers: [Customer] = []

    init(mockCustomers: [Customer]? = nil) {
        if let mockCustomers {
            self.customers = mockCustomers.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            self.allMockCustomers = self.customers
            self.state = .loaded
            self.isMock = true
        }
    }

    func load(query: String? = nil) async {
        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines)

        if isMock {
            if let trimmed, !trimmed.isEmpty {
                customers = allMockCustomers.filter { customer in
                    customer.name.localizedCaseInsensitiveContains(trimmed) ||
                    (customer.phone?.localizedCaseInsensitiveContains(trimmed) ?? false)
                }
            } else {
                customers = allMockCustomers
            }
            state = .loaded
            return
        }

        if customers.isEmpty {
            state = .loading
        }
        actionErrorMessage = nil

        var queryItems: [URLQueryItem] = []
        if let trimmed, !trimmed.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: trimmed))
        }

        do {
            let list: [Customer] = try await NetworkService.shared.request(
                .get,
                "/customers/",
                query: queryItems
            )
            self.customers = list
            self.state = .loaded
        } catch let apiError as APIError {
            self.state = .error(apiError.localizedDescription)
        } catch {
            self.state = .error(error.localizedDescription)
        }
    }

    func deleteCustomer(id: String) async {
        actionErrorMessage = nil
        if isMock {
            removeCustomer(id: id)
            return
        }

        do {
            try await NetworkService.shared.requestNoContent(.delete, "/customers/\(id)")
            removeCustomer(id: id)
        } catch let apiError as APIError {
            actionErrorMessage = apiError.localizedDescription
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    /// Agrega o reemplaza un cliente por id, manteniendo la lista ordenada por nombre. Usado por I7b.
    func upsertCustomer(_ customer: Customer) {
        if let index = customers.firstIndex(where: { $0.id == customer.id }) {
            customers[index] = customer
        } else {
            customers.append(customer)
        }
        customers.sort { $0.name.localizedCompare($1.name) == .orderedAscending }

        if isMock {
            if let index = allMockCustomers.firstIndex(where: { $0.id == customer.id }) {
                allMockCustomers[index] = customer
            } else {
                allMockCustomers.append(customer)
            }
            allMockCustomers.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        }
    }

    func removeCustomer(id: String) {
        customers.removeAll { $0.id == id }
        if isMock {
            allMockCustomers.removeAll { $0.id == id }
        }
    }
}
