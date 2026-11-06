import Foundation
import Observation
import KitchenDomain

/// Maneja el vaciado de datos de AyeKitchen y la eliminación de la cuenta Aye (Bloque I29).
@Observable
final class DataDeletionModel {
    var isWorking = false
    var errorMessage: String?

    @discardableResult
    func eraseKitchenData(accountId: String) async -> Bool {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        #if DEBUG
        if DebugAccount.isActive {
            LocalReset.eraseAllData(accountId: accountId)
            return true
        }
        #endif

        do {
            try await NetworkService.shared.requestNoContent(.delete, "/me/data")
            LocalReset.eraseAllData(accountId: accountId)
            return true
        } catch {
            if isNoInternet(error) {
                errorMessage = "Necesitas internet para borrar tus datos. No se borró nada."
            } else {
                errorMessage = error.localizedDescription
            }
            return false
        }
    }

    @discardableResult
    func deleteAyeAccount(accountId: String, session: SessionStore) async -> Bool {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        #if DEBUG
        if DebugAccount.isActive {
            LocalReset.forgetAccountOnThisPhone(accountId: accountId)
            await session.signOut()
            return true
        }
        #endif

        // (a) Borrar lo de Kitchen en el servidor.
        do {
            try await NetworkService.shared.requestNoContent(.delete, "/me/")
        } catch {
            if isNoInternet(error) {
                errorMessage = "Necesitas internet para borrar tus datos. No se borró nada."
            } else {
                errorMessage = error.localizedDescription
            }
            return false
        }

        // (b) Borrar la cuenta Aye en aye-auth.
        do {
            try await NetworkService.shared.deleteAyeAccount()
        } catch {
            errorMessage = "Tus datos de AyeKitchen ya se borraron, pero no pudimos eliminar tu cuenta Aye. Intenta de nuevo."
            return false
        }

        // (c) Limpiar todo rastro local de la cuenta.
        LocalReset.forgetAccountOnThisPhone(accountId: accountId)

        // (d) Cerrar la sesión para volver a la pantalla de entrar.
        await session.signOut()
        return true
    }

    private func isNoInternet(_ error: Error) -> Bool {
        if let apiError = error as? APIError {
            switch apiError {
            case .network(let urlError):
                return isNetworkConnectionError(urlError)
            default:
                return false
            }
        }
        if let urlError = error as? URLError {
            return isNetworkConnectionError(urlError)
        }
        return false
    }

    private func isNetworkConnectionError(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .dataNotAllowed,
             .cannotConnectToHost,
             .cannotFindHost,
             .timedOut,
             .dnsLookupFailed,
             .internationalRoamingOff:
            return true
        default:
            return error.code != .badServerResponse
        }
    }
}
