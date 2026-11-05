import Foundation
import Observation

enum CustomersLoadingState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case error(String)
}

/// ViewModel para la lista de clientes (`CustomersView`, MVVM, Regla 5 / Bloque I13).
@Observable final class CustomersModel {
    var customers: [Customer] = []
    var state: CustomersLoadingState = .idle
    var actionErrorMessage: String? = nil
    private(set) var isMock: Bool = false
    private var allMockCustomers: [Customer] = []
    private var hasLoadedOnce: Bool = false
    private(set) var currentSearchQuery: String? = nil

    var isSearching: Bool {
        guard let query = currentSearchQuery?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !query.isEmpty
    }

    init(mockCustomers: [Customer]? = nil) {
        if let mockCustomers {
            self.customers = mockCustomers.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            self.allMockCustomers = self.customers
            self.state = .loaded
            self.isMock = true
            self.hasLoadedOnce = true
        }
    }

    /// Carga la primera pantalla (desde caché si existe) o ejecuta la búsqueda activa.
    func load(query: String? = nil) async {
        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSearch = !(trimmed?.isEmpty ?? true)
        currentSearchQuery = isSearch ? trimmed : nil

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

        if isSearch {
            if customers.isEmpty {
                state = .loading
            }
            actionErrorMessage = nil
            do {
                let list: [Customer] = try await NetworkService.shared.request(
                    .get,
                    "/customers/",
                    query: [URLQueryItem(name: "q", value: trimmed!)]
                )
                self.customers = list
                self.state = .loaded
            } catch let apiError as APIError {
                self.state = .error(apiError.localizedDescription)
            } catch {
                self.state = .error(error.localizedDescription)
            }
            return
        }

        // Sin búsqueda activa: primera pantalla
        if hasLoadedOnce {
            await reloadIfStale()
        } else {
            if await loadFromCache() {
                await reloadIfStale()
            } else {
                state = .loading
                await forceReload()
            }
        }
    }

    /// Pull-to-refresh
    func refresh(query: String? = nil) async {
        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            await load(query: trimmed)
        } else {
            await forceReload()
        }
    }

    func forceReload() async {
        guard !isMock else { return }
        await ChangeTracker.shared.forceReload(.customers) {
            await self.reloadSilently()
        }
    }

    func reloadIfStale() async {
        guard !isMock, !isSearching else { return }
        await ChangeTracker.shared.reloadIfStale(.customers) {
            await self.reloadSilently()
        }
    }

    /// Lee la copia guardada en disco de la primera pantalla sin búsqueda.
    private func loadFromCache() async -> Bool {
        guard !isMock else { return true }
        guard let list: [Customer] = await NetworkService.shared.cached("/customers/", query: []) else {
            return false
        }
        self.customers = list
        self.hasLoadedOnce = true
        self.state = .loaded
        return true
    }

    /// Recarga en silencio sin pasar por estado de carga. Guarda la respuesta en disco con requestCaching.
    @discardableResult
    func reloadSilently() async -> Bool {
        guard !isMock else { return true }
        do {
            let list: [Customer] = try await NetworkService.shared.requestCaching(
                "/customers/",
                query: []
            )
            self.customers = list
            self.hasLoadedOnce = true
            self.state = .loaded
            return true
        } catch {
            if !hasLoadedOnce {
                self.state = .error(error.localizedDescription)
            }
            return false
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
