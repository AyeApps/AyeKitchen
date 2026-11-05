import Foundation
import SwiftUI

// MARK: - Modelo de Detalle de Marca

@Observable final class BrandDetailModel {
    var presentation: RemotePresentation
    var prices: [RemotePriceRecord] = []
    var isLoadingPrices = false
    var errorMessage: String?

    init(presentation: RemotePresentation, mockPrices: [RemotePriceRecord]? = nil) {
        self.presentation = presentation
        if let mockPrices {
            self.prices = mockPrices
        }
    }

    func loadPrices() async {
        isLoadingPrices = true
        errorMessage = nil
        do {
            let list: [RemotePriceRecord] = try await NetworkService.shared.request(
                .get,
                "/presentations/\(presentation.id)/prices"
            )
            self.prices = list
            self.isLoadingPrices = false
        } catch where error.isCancellation {
            self.isLoadingPrices = false
        } catch {
            self.isLoadingPrices = false
            self.errorMessage = error.localizedDescription
        }
    }

    func reload() async {
        do {
            async let presTask: RemotePresentation = NetworkService.shared.request(
                .get,
                "/presentations/\(presentation.id)"
            )
            async let pricesTask: [RemotePriceRecord] = NetworkService.shared.request(
                .get,
                "/presentations/\(presentation.id)/prices"
            )

            let (updatedPres, updatedPrices) = try await (presTask, pricesTask)
            self.presentation = updatedPres
            self.prices = updatedPrices
        } catch where error.isCancellation {
            // Cancelado: no mostrar error ni cambiar datos existentes
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}
