import SwiftUI

/// Hoja de ayuda permanente sobre equivalencias de medidas (Bloque I30).
struct ConversionsHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    paragraph("Tus recetas dicen tazas, cucharadas o pizcas, pero compras por peso, litro o pieza.")
                    paragraph("Una equivalencia nos dice cuánto pesa (o mide) una de esas medidas para este ingrediente. Ejemplo: 1 taza de harina = 125 g; 1 taza de azúcar = 200 g.")
                    paragraph("Cada ingrediente pesa distinto, por eso se pone en cada uno. Si una receta usa una medida que no tiene equivalencia, te la preguntamos en ese momento.")
                    paragraph("Si no sabes cuánto pesa, mídelo una vez en tu báscula y anótalo.")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(.canvasBackground)
            .navigationTitle("Equivalencias")
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
#Preview("Equivalencias") {
    ConversionsHelpSheet()
}

#Preview("Equivalencias - AX3") {
    ConversionsHelpSheet()
        .dynamicTypeSize(.accessibility3)
}
#endif
