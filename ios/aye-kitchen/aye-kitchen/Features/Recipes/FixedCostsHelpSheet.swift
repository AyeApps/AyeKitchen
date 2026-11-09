import SwiftUI

/// Hoja de ayuda permanente sobre costos fijos de una receta (Bloque I30).
struct FixedCostsHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    paragraph("Son gastos de la receta que no son ingredientes: la caja, la base de cartón, la vela, el gas o la luz del horno.")
                    paragraph("Pon cuánto te cuesta cada uno por tanda. Se suman a lo que te cuesta la receta y se toman en cuenta en el precio que te sugerimos.")
                    paragraph("Ejemplo: caja $25 y gas $10 → la receta te cuesta $35 más.")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(.canvasBackground)
            .navigationTitle("Costos fijos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.inkPrimary)
            .padding(.vertical, Spacing.xs)
    }
}

#if DEBUG
#Preview("Costos fijos") {
    FixedCostsHelpSheet()
}

#Preview("Costos fijos - AX3") {
    FixedCostsHelpSheet()
        .dynamicTypeSize(.accessibility3)
}
#endif
