#if DEBUG
import SwiftUI

/// Muestrario de los componentes para revisarlos en el Canvas de Xcode (claro, oscuro y letra grande).
private struct DesignGallery: View {
    @State private var text = "Harina de trigo"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Lo que sigue")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(.accentTextDeep)
                    Text("Mañana, 4:00 pm")
                        .font(.title2.weight(.heavy))
                    Text("Pastel de chocolate 20 cm · 12 porciones")
                        .font(.callout)
                        .foregroundStyle(.inkOnSoft)
                }
                .softCard()

                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Esta semana").sectionTitleStyle()
                    RowGroup {
                        ForEach(OrderStatus.allCases, id: \.self) { status in
                            HStack {
                                Text("Pedido de ejemplo").font(.headline)
                                Spacer()
                                StatusChip(status: status)
                            }
                            .padding(14)
                        }
                    }
                }

                HStack {
                    Chip("Falta precio", tone: .warning)
                    Chip("Precio viejo", tone: .warning)
                }

                Text(Money.format(cents: 18640))
                    .font(.largeTitle.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(.tint)

                KitchenTextField(label: "Ingrediente", text: $text)

                Button("Agregar a la receta") {}
                    .buttonStyle(.kitchenPrimary)
                Button("Continuar con Google") {}
                    .buttonStyle(.kitchenSecondary)
                Button("Cancelar") {}
                    .fontWeight(.semibold)
            }
            .padding(Spacing.xl)
        }
        .background(.canvasBackground)
        .foregroundStyle(.inkPrimary)
        .fontDesign(.rounded)
    }
}

#Preview("Claro") {
    DesignGallery()
}

#Preview("Oscuro") {
    DesignGallery()
        .preferredColorScheme(.dark)
}

#Preview("Letra AX3") {
    DesignGallery()
        .dynamicTypeSize(.accessibility3)
}
#endif
