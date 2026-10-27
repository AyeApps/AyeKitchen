import SwiftUI

extension View {
    /// Tarjeta crema para lo más importante de la pantalla ("Lo que sigue", el costo de la receta,
    /// la pregunta de equivalencia). Una por pantalla, máximo dos. Nunca tarjetas dentro de tarjetas.
    func softCard() -> some View {
        padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.accentSoft, in: .rect(cornerRadius: Radius.card))
    }

    /// Título de sección dentro de una pantalla ("Esta semana", "De dónde sale el costo").
    func sectionTitleStyle() -> some View {
        font(.title3.weight(.heavy))
            .foregroundStyle(.inkPrimary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Filas en un contenedor con borde de 1 pt, radio 16 y divisores entre filas
/// (como la lista agrupada de iOS, dentro de un ScrollView).
struct RowGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(rows) { row in
                    if row.id != rows.first?.id {
                        Rectangle()
                            .fill(.dividerLine)
                            .frame(height: 1)
                    }
                    row
                }
            }
        }
        .background(.surfaceCard, in: .rect(cornerRadius: Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(.borderLine, lineWidth: 1)
        }
        .clipShape(.rect(cornerRadius: Radius.card))
    }
}
