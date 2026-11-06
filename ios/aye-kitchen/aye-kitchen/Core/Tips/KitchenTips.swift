import SwiftUI
import TipKit

/// Consejos en contexto (TipKit). Los textos los aprobó el usuario (2026-11-06); no los cambies
/// sin preguntar. Cada pantalla coloca SU consejo con `TipView(...)` (en línea, dentro de una
/// lista) o `.popoverTip(...)` (sobre un botón), según diga el bloque I25.
///
/// Reglas: algunos consejos solo salen cuando tiene sentido. La pantalla prende su parámetro
/// (`IngredientCurrentBrandTip.ingredientHasBrands = true`) cuando se cumple la condición.
/// Una vez que la persona cierra un consejo, no vuelve a salir.
enum KitchenTips {
    private static let resetKey = "KitchenTips.resetOnNextLaunch"

    /// Llamar una sola vez al arrancar la app (`AyeKitchenApp`).
    static func configure() {
        if UserDefaults.standard.bool(forKey: resetKey) {
            try? Tips.resetDatastore()
            UserDefaults.standard.set(false, forKey: resetKey)
        }
        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.applicationDefault),
        ])
    }

    /// "Volver a ver los consejos" (Ajustes). TipKit solo se puede reiniciar antes de configurarse,
    /// así que se aplica la próxima vez que se abre la app.
    static func requestResetOnNextLaunch() {
        UserDefaults.standard.set(true, forKey: resetKey)
    }
}

// MARK: - Catálogo

/// Lista del Catálogo.
struct CatalogBrandsTip: Tip {
    var title: Text { Text("Un ingrediente, varias marcas") }
    var message: Text? {
        Text("Registra Harina de trigo una vez y agrégale Selecta, Tres Estrellas o las marcas que compres.")
    }
    var image: Image? { Image(systemName: "square.stack.3d.up") }
}

/// Sección de marcas de un ingrediente, cuando ya tiene al menos una marca.
struct IngredientCurrentBrandTip: Tip {
    @Parameter static var ingredientHasBrands: Bool = false

    var title: Text { Text("La que usamos") }
    var message: Text? {
        Text("Es la marca con el precio más reciente. Tus recetas la usan si no eliges otra.")
    }
    var image: Image? { Image(systemName: "checkmark.seal") }
    var rules: [Rule] {
        #Rule(Self.$ingredientHasBrands) { $0 == true }
    }
}

/// Sección "Equivalencias" del formulario de ingrediente (I30).
struct IngredientConversionsTip: Tip {
    var title: Text { Text("¿Cuánto pesa una taza?") }
    var message: Text? {
        Text("Si tus recetas dicen tazas o cucharadas, dinos cuánto pesa una de este ingrediente. Ejemplo: 1 taza de harina = 125 g.")
    }
    var image: Image? { Image(systemName: "scalemass") }
}

/// Tamaño del paquete al agregar una marca (I30).
struct BrandPackageSizeTip: Tip {
    var title: Text { Text("Lo que trae el paquete") }
    var message: Text? {
        Text("Pon lo que dice la etiqueta: 1 kg, 900 ml o 12 piezas. Con el precio sabemos cuánto te cuesta cada gramo.")
    }
    var image: Image? { Image(systemName: "shippingbox") }
}

/// Botón de Tiendas en el Catálogo (I30).
struct CatalogStoresTip: Tip {
    var title: Text { Text("Tus tiendas") }
    var message: Text? { Text("Aquí agregas, cambias de nombre o borras las tiendas donde compras.") }
    var image: Image? { Image(systemName: "storefront") }
}

// MARK: - Recetas

/// "¿Cuánto rinde?" en el editor de recetas (I30).
struct RecipeYieldTip: Tip {
    var title: Text { Text("Cuánto sale") }
    var message: Text? {
        Text("Cuántas piezas o porciones te salen. Con esto te decimos cuánto cuesta cada una.")
    }
    var image: Image? { Image(systemName: "square.grid.2x2") }
}

/// "Costos fijos" en el editor de recetas (I30).
struct RecipeFixedCostsTip: Tip {
    var title: Text { Text("Lo que no es ingrediente") }
    var message: Text? {
        Text("Agrega la caja, el gas o la luz que gasta esta receta. Se suman a lo que te cuesta.")
    }
    var image: Image? { Image(systemName: "flame") }
}

/// Selector de ingredientes de una receta, donde también salen otras recetas (I30).
struct RecipeSubrecipeTip: Tip {
    var title: Text { Text("Una receta dentro de otra") }
    var message: Text? {
        Text("El betún o el relleno pueden ser recetas propias. Agrégalas a tu pastel como si fueran un ingrediente.")
    }
    var image: Image? { Image(systemName: "square.on.square") }
}

/// Desglose de costo en el detalle de una receta.
struct RecipeChangeBrandTip: Tip {
    var title: Text { Text("Costea con otra marca") }
    var message: Text? { Text("Toca un ingrediente para costear con otra marca.") }
    var image: Image? { Image(systemName: "hand.tap") }
}

/// Selector de versiones del detalle de una receta, cuando algún ingrediente de la receta tiene
/// dos o más marcas.
struct RecipeVersionsTip: Tip {
    @Parameter static var recipeHasIngredientWithSeveralBrands: Bool = false

    var title: Text { Text("Compara marcas") }
    var message: Text? { Text("Crea versiones para comparar cuánto te sale con distintas marcas.") }
    var image: Image? { Image(systemName: "square.split.2x1") }
    var rules: [Rule] {
        #Rule(Self.$recipeHasIngredientWithSeveralBrands) { $0 == true }
    }
}

// MARK: - Pedidos

/// Formulario de pedido, cuando una línea es de una receta que rinde más de 1.
struct OrderSoldByTip: Tip {
    @Parameter static var hasRecipeYieldingSeveral: Bool = false

    var title: Text { Text("Por pieza o por tanda") }
    var message: Text? { Text("Vende por pieza o por tanda completa.") }
    var image: Image? { Image(systemName: "square.grid.3x3") }
    var rules: [Rule] {
        #Rule(Self.$hasRecipeYieldingSeveral) { $0 == true }
    }
}

// MARK: - Finanzas y Ajustes

/// Pestaña Finanzas, sección del mes.
struct FinanceExpensesTip: Tip {
    var title: Text { Text("Registra tus gastos") }
    var message: Text? { Text("Registra tus gastos para saber cuánto te queda de verdad.") }
    var image: Image? { Image(systemName: "cart") }
}

/// Fila de Respaldo en Ajustes.
struct BackupTip: Tip {
    var title: Text { Text("Tus datos están a salvo") }
    var message: Text? { Text("Tus datos viven en tu teléfono y se respaldan solos.") }
    var image: Image? { Image(systemName: "icloud.and.arrow.up") }
}
