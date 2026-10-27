import Foundation
import SwiftUI

// MARK: - Modelo de Detalle de Marca

@Observable final class BrandDetailModel {
    var presentation: Presentation
    var prices: [PriceRecord] = []
    var isLoadingPrices = false
    var errorMessage: String?

    init(presentation: Presentation, mockPrices: [PriceRecord]? = nil) {
        self.presentation = presentation
        if let mockPrices {
            self.prices = mockPrices
        }
    }

    func loadPrices() async {
        isLoadingPrices = true
        errorMessage = nil
        do {
            let list: [PriceRecord] = try await NetworkService.shared.request(
                .get,
                "/presentations/\(presentation.id)/prices"
            )
            self.prices = list
            self.isLoadingPrices = false
        } catch {
            self.isLoadingPrices = false
            self.errorMessage = error.localizedDescription
        }
    }

    func reload() async {
        do {
            async let presTask: Presentation = NetworkService.shared.request(
                .get,
                "/presentations/\(presentation.id)"
            )
            async let pricesTask: [PriceRecord] = NetworkService.shared.request(
                .get,
                "/presentations/\(presentation.id)/prices"
            )

            let (updatedPres, updatedPrices) = try await (presTask, pricesTask)
            self.presentation = updatedPres
            self.prices = updatedPrices
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}
