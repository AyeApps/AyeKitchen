import Foundation
import KitchenDomain
import Observation

// MARK: - Modelo para Registrar Precio

@Observable final class RecordPriceModel {
    let presentationId: String
    private let store: LocalStore

    var priceText: String = ""
    var recordedAt: Date = Date()
    var noteText: String = ""
    var errorMessage: String?

    init(presentationId: String, store: LocalStore = .shared) {
        self.presentationId = presentationId
        self.store = store
    }

    var parsedPriceCents: Int? {
        Self.parsePriceCents(priceText)
    }

    var canSave: Bool {
        parsedPriceCents != nil
    }

    static func parsePriceCents(_ text: String) -> Int? {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
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

    func save() -> Bool {
        guard let cents = parsedPriceCents else { return false }
        errorMessage = nil

        let trimmedNote = noteText.trimmingCharacters(in: .whitespaces)
        let note = trimmedNote.isEmpty ? nil : trimmedNote

        do {
            try store.mutate { data, ctx in
                try data.addPrice(
                    presentationId: presentationId,
                    priceCents: cents,
                    recordedAt: recordedAt,
                    note: note,
                    ctx: ctx
                )
            }
            return true
        } catch let domainError as DomainError {
            self.errorMessage = domainError.detail
            return false
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }
}
