import SwiftUI

/// Hoja de ayuda para orientar la elección de la unidad base según cómo se mide el ingrediente en las recetas.
struct BaseUnitHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    optionRow(
                        title: "Se pesa",
                        text: "Harina, azúcar, queso, chocolate. También la mantequilla: aunque la compres por barra, si en la receta la pesas, elige Se pesa. Una barra de 90 g se registra como un paquete de 90 g."
                    )

                    optionRow(
                        title: "Es líquido",
                        text: "Leche, aceite, crema, vainilla, agua. Lo mides en ml, litros, tazas o cucharadas."
                    )

                    optionRow(
                        title: "Se cuenta",
                        text: "Huevos, latas, tortillas, cajas. Si tu receta dice 1 barra de mantequilla, también puedes elegir Se cuenta."
                    )
                } header: {
                    Text("Elige según cómo lo mides en tus recetas, no según cómo lo compras.")
                        .font(.subheadline)
                        .foregroundStyle(.inkPrimary)
                        .textCase(nil)
                } footer: {
                    Text("Cuando el ingrediente ya tenga marcas o lo use una receta, esto ya no se puede cambiar.")
                        .font(.footnote)
                        .foregroundStyle(.inkMuted)
                        .textCase(nil)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(.canvasBackground)
            .navigationTitle("¿Cuál elijo?")
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

    private func optionRow(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.inkPrimary)

            Text(text)
                .font(.body)
                .foregroundStyle(.inkPrimary)
        }
        .padding(.vertical, Spacing.xs)
    }
}

#if DEBUG
#Preview("¿Cuál elijo?") {
    BaseUnitHelpSheet()
}

#Preview("¿Cuál elijo? - AX3") {
    BaseUnitHelpSheet()
        .dynamicTypeSize(.accessibility3)
}
#endif
