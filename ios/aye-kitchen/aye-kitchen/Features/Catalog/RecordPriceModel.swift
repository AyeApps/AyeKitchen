import Foundation
import SwiftUI

// MARK: - Cuerpos de petición (docs/api-contract.md)

nonisolated struct PriceRecordCreateRequest: Encodable, Sendable {
    let priceCents: Int
    let recordedAt: Date
    let note: String?
}

// MARK: - Modelo para Registrar Precio

@Observable final class RecordPriceModel {
    let presentationId: String

    var priceText: String = ""
    var recordedAt: Date = Date()
    var noteText: String = ""
    var isSaving: Bool = false
    var errorMessage: String?

    init(presentationId: String) {
        self.presentationId = presentationId
    }

    var parsedPriceCents: Int? {
        let normalized = priceText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty,
              let decimal = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
              decimal >= 0 else {
            return nil
        }
        var centsDecimal = decimal * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &centsDecimal, 0, .plain)
        return (rounded as NSDecimalNumber).intValue
    }

    var canSave: Bool {
        parsedPriceCents != nil && !isSaving
    }

    func save() async -> Bool {
        guard let cents = parsedPriceCents else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let trimmedNote = noteText.trimmingCharacters(in: .whitespaces)
        let note = trimmedNote.isEmpty ? nil : trimmedNote

        let body = PriceRecordCreateRequest(
            priceCents: cents,
            recordedAt: recordedAt,
            note: note
        )

        do {
            let _: PriceRecord = try await NetworkService.shared.request(
                .post,
                "/presentations/\(presentationId)/prices",
                body: body
            )
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }
}
