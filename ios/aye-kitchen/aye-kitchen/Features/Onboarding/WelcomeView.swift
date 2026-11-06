import SwiftUI

/// Bienvenida antes de Entrar (Bloque I28).
/// Tres páginas deslizables que explican para qué sirve la app antes de entrar con la cuenta.
struct WelcomeView: View {
    /// Llamar al terminar o al tocar "Saltar": `RootView` marca la bienvenida como vista y muestra Entrar.
    let onFinish: () -> Void

    @State private var currentPage = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ScaledMetric(relativeTo: .largeTitle) private var logoSize: CGFloat = 56
    @ScaledMetric(relativeTo: .largeTitle) private var circleSize: CGFloat = 112

    private struct PageItem: Identifiable {
        let id: Int
        let showLogo: Bool
        let icon: String
        let title: String
        let phrase: String
    }

    private let pages: [PageItem] = [
        PageItem(
            id: 0,
            showLogo: true,
            icon: "birthday.cake",
            title: "Sabe cuánto te cuesta cada pastel",
            phrase: "Arma tus recetas con los precios de tus tiendas y te decimos cuánto te cuesta y cuánto cobrar."
        ),
        PageItem(
            id: 1,
            showLogo: false,
            icon: "list.clipboard",
            title: "Tus pedidos, en orden",
            phrase: "Anota la fecha de entrega, el anticipo y lo que te falta cobrar. Todo en un solo lugar."
        ),
        PageItem(
            id: 2,
            showLogo: false,
            icon: "iphone",
            title: "Todo vive en tu teléfono",
            phrase: "Funciona sin internet. Tu información se respalda sola en tu cuenta Aye."
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            topBar

            TabView(selection: $currentPage) {
                ForEach(pages) { page in
                    pageContent(for: page)
                        .tag(page.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            // Sin fondo, los puntos son blancos y no se ven sobre el crema.
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            bottomBar
        }
        .background(.canvasBackground)
    }

    // MARK: - Barra superior

    private var topBar: some View {
        HStack {
            Spacer()
            if currentPage < 2 {
                Button("Saltar") {
                    onFinish()
                }
                .font(.body.weight(.bold))
                .foregroundStyle(.tint)
                .frame(minHeight: 44)
            }
        }
        .frame(height: 44)
        .padding(.horizontal, Spacing.xxl)
        .padding(.top, Spacing.sm)
    }

    // MARK: - Contenido de página

    private func pageContent(for page: PageItem) -> some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    if page.showLogo {
                        Image(.appLogo)
                            .resizable()
                            .scaledToFit()
                            .padding(logoSize * 0.14)
                            .frame(width: logoSize, height: logoSize)
                            .background(.accentFill, in: .rect(cornerRadius: Radius.primaryButton))
                            .accessibilityHidden(true)
                    }
    
                    Circle()
                        .fill(.accentSoft)
                        .frame(width: circleSize, height: circleSize)
                        .overlay {
                            Image(systemName: page.icon)
                                .font(.largeTitle.weight(.semibold))
                                .imageScale(.large)
                                .foregroundStyle(.tint)
                        }
                        .accessibilityHidden(true)
    
                    VStack(spacing: Spacing.sm) {
                        Text(page.title)
                            .font(.title2.weight(.heavy))
                            .foregroundStyle(.inkPrimary)
    
                        Text(page.phrase)
                            .font(.body)
                            .foregroundStyle(.inkMuted)
                    }
                    .multilineTextAlignment(.center)
                    .accessibilityElement(children: .combine)
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.top, Spacing.xl)
                .padding(.bottom, 48)
                // Centrado en la pantalla; con letra grande crece y se desplaza.
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: - Barra inferior

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Button(currentPage < 2 ? "Siguiente" : "Empezar") {
                advance()
            }
            .buttonStyle(.kitchenPrimary)
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.lg)
    }

    private func advance() {
        if currentPage < 2 {
            if reduceMotion {
                currentPage += 1
            } else {
                withAnimation {
                    currentPage += 1
                }
            }
        } else {
            onFinish()
        }
    }
}

#if DEBUG
#Preview("Normal") {
    WelcomeView(onFinish: {})
}

#Preview("Accesibilidad AX3") {
    WelcomeView(onFinish: {})
        .dynamicTypeSize(.accessibility3)
}

#Preview("Modo oscuro") {
    WelcomeView(onFinish: {})
        .preferredColorScheme(.dark)
}
#endif
