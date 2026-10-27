import SwiftUI

/// Hoja para capturar un costo fijo adicional para la receta (caja, gas, etc.).
struct AddExtraCostSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var amountText: String = ""

    let onAdd: @MainActor @Sendable (ExtraCost) -> Void

    private var parsedCents: Int? {
        let clean = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !clean.isEmpty,
              let dec = Decimal(string: clean, locale: Locale(identifier: "en_US_POSIX")),
              dec > 0 else {
            return nil
        }
        let inCents = dec * 100
        var rounded = Decimal()
        var copy = inCents
        NSDecimalRound(&rounded, &copy, 0, .plain)
        return (rounded as NSDecimalNumber).intValue
    }

    private var canAdd: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, let cents = parsedCents, cents > 0 else {
            return false
        }
        return true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    KitchenTextField(
                        label: "¿Qué es?",
                        text: $name
                    )

                    KitchenTextField(
                        label: "¿Cuánto cuesta?",
                        text: $amountText,
                        keyboard: .decimalPad
                    )

                    Button {
                        if let cents = parsedCents {
                            let trimmedName = name.trimmingCharacters(in: .whitespaces)
                            onAdd(ExtraCost(name: trimmedName, costCents: cents))
                            dismiss()
                        }
                    } label: {
                        Text("Agregar costo fijo")
                    }
                    .buttonStyle(.kitchenPrimary)
                    .disabled(!canAdd)
                }
                .padding(Spacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(.canvasBackground)
            .navigationTitle("Costo fijo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
                }
            }
        }
    }
}
