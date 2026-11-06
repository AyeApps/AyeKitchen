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

// MARK: - Recetas

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
