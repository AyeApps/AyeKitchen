import SwiftUI
import KitchenDomain

// MARK: - Estado compartido del tamaño del paquete

@Observable
final class PackageSizeInput {
    let store: LocalStore
    var quantityText: String
    var selectedUnit: KitchenUnit?
    var packItemQuantityText: String
    var selectedPackItemUnit: KitchenUnit?
    var baseUnit: BaseUnit
    var conversions: [IngredientConversion]

    init(
        store: LocalStore = .shared,
        baseUnit: BaseUnit = .g,
        conversions: [IngredientConversion] = [],
        quantityText: String = "1",
        packItemQuantityText: String = ""
    ) {
        self.store = store
        self.baseUnit = baseUnit
        self.conversions = conversions
        self.quantityText = quantityText
        self.packItemQuantityText = packItemQuantityText
        selectDefaultUnit()
        selectDefaultPackItemUnit()
    }

    // MARK: - Unidades del menú principal

    /// Unidades del menú principal, en orden y sin repetir:
    /// 1. Las de la misma unidad base del ingrediente (primero la de factor "1").
    /// 2. Si la base NO es pieza, las unidades de base pieza (pz, docena...).
    /// 3. Las unidades que tengan una equivalencia en el ingrediente y no estén ya en la lista.
    var availableUnits: [KitchenUnit] {
        let all = store.data.availableKitchenUnits()
        var result: [KitchenUnit] = []
        var seenIds = Set<String>()

        func appendUnits(_ list: [KitchenUnit]) {
            for u in list {
                if !seenIds.contains(u.id) {
                    seenIds.insert(u.id)
                    result.append(u)
                }
            }
        }

        // 1. Misma base del ingrediente (primero factor "1")
        let sameBase = all.filter { $0.baseUnit == baseUnit }
        if let factorOne = sameBase.first(where: { $0.factorToBase == "1" }) {
            appendUnits([factorOne])
        }
        appendUnits(sameBase)

        // 2. Si la base NO es pieza, unidades de base pieza (primero factor "1")
        if baseUnit != .pz {
            let pzUnits = all.filter { $0.baseUnit == .pz }
            if let pzFactorOne = pzUnits.first(where: { $0.factorToBase == "1" }) {
                appendUnits([pzFactorOne])
            }
            appendUnits(pzUnits)
        }

        // 3. Unidades con equivalencia en el ingrediente
        let convUnitIds = Set(conversions.map(\.unitId))
        let convUnits = all.filter { convUnitIds.contains($0.id) }
        appendUnits(convUnits)

        return result
    }

    /// Unidades para "Cada pieza trae": solo las de la misma base del ingrediente,
    /// por defecto la de factor "1".
    var availablePackItemUnits: [KitchenUnit] {
        let all = store.data.availableKitchenUnits()
        let sameBase = all.filter { $0.baseUnit == baseUnit }
        var result: [KitchenUnit] = []
        if let factorOne = sameBase.first(where: { $0.factorToBase == "1" }) {
            result.append(factorOne)
        }
        for u in sameBase where u.id != result.first?.id {
            result.append(u)
        }
        return result
    }

    // MARK: - Modo piezas

    /// Verdadero cuando el ingrediente NO es de base pieza y la unidad elegida es de base pieza.
    var isPiecesMode: Bool {
        baseUnit != .pz && selectedUnit?.baseUnit == .pz
    }

    /// Número de piezas en modo piezas: cantidad × factorToBase de la unidad (ej. 2 docenas = 24).
    var piecesDecimal: Decimal? {
        guard isPiecesMode,
              let parsed = Quantity.parse(quantityText),
              let qtyDec = Decimal(string: parsed),
              let unit = selectedUnit,
              let factor = Decimal(string: unit.factorToBase),
              factor > 0 else {
            return nil
        }
        return qtyDec * factor
    }

    /// Comprueba si el número de piezas calculado es un entero.
    var isPiecesInteger: Bool {
        guard let pieces = piecesDecimal else { return false }
        var rounded = Decimal()
        var copy = pieces
        NSDecimalRound(&rounded, &copy, 0, .plain)
        return rounded == pieces
    }

    /// Número entero de piezas entre 1 y 10,000 en modo piezas; nulo si no es válido.
    var packCount: Int? {
        guard isPiecesMode,
              let pieces = piecesDecimal,
              isPiecesInteger else {
            return nil
        }
        let count = (pieces as NSDecimalNumber).intValue
        guard count >= 1 && count <= 10_000 else {
            return nil
        }
        return count
    }

    /// Mensaje de aviso cuando las piezas son inválidas en modo piezas.
    var piecesWarningText: String? {
        guard isPiecesMode else { return nil }
        let trimmed = quantityText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard let pieces = piecesDecimal else { return nil }
        if !isPiecesInteger {
            return "Las piezas tienen que ser un número entero."
        }
        let count = (pieces as NSDecimalNumber).intValue
        if count < 1 || count > 10_000 {
            return "Las piezas del paquete deben ser entre 1 y 10,000."
        }
        return nil
    }

    // MARK: - Validez y Total

    var isValid: Bool {
        if isPiecesMode {
            guard packCount != nil else { return false }
            guard Quantity.parse(packItemQuantityText) != nil else { return false }
            guard selectedPackItemUnit != nil else { return false }
            return true
        } else {
            guard Quantity.parse(quantityText) != nil else { return false }
            guard selectedUnit != nil else { return false }
            return true
        }
    }

    /// Total en la unidad base cuando se puede calcular.
    var totalInBase: Decimal? {
        guard isValid else { return nil }
        if isPiecesMode {
            guard let count = packCount,
                  let itemQtyStr = Quantity.parse(packItemQuantityText),
                  let itemQtyDec = Decimal(string: itemQtyStr),
                  let packItemUnit = selectedPackItemUnit,
                  let factor = Decimal(string: packItemUnit.factorToBase),
                  factor > 0 else {
                return nil
            }
            let itemInBase = itemQtyDec * factor
            return Decimal(count) * itemInBase
        } else {
            guard let qtyStr = Quantity.parse(quantityText),
                  let qtyDec = Decimal(string: qtyStr),
                  let unit = selectedUnit else {
                return nil
            }
            if unit.baseUnit == baseUnit {
                let factor = Decimal(string: unit.factorToBase) ?? 1
                return qtyDec * factor
            } else if let conv = conversions.first(where: { $0.unitId == unit.id }),
                      let convDec = Decimal(string: conv.quantityInBase) {
                return qtyDec * convDec
            }
            return nil
        }
    }

    var totalInBaseText: String? {
        guard let total = totalInBase else { return nil }
        return "\(Quantity.format(Qty.text(total))) \(baseUnit.rawValue)"
    }

    // MARK: - Métodos de cambio y carga

    func selectUnit(_ unit: KitchenUnit) {
        let wasPiecesMode = isPiecesMode
        selectedUnit = unit
        if !wasPiecesMode && isPiecesMode {
            onEnterPiecesMode()
        }
    }

    private func onEnterPiecesMode() {
        selectDefaultPackItemUnit()
        if let conv = conversions.first(where: { $0.unitId == "sys.pz" }) {
            packItemQuantityText = Quantity.format(conv.quantityInBase).replacingOccurrences(of: ",", with: "")
        }
    }

    func selectDefaultUnit() {
        let units = availableUnits
        if let matchOne = units.first(where: { $0.baseUnit == baseUnit && $0.factorToBase == "1" }) {
            selectedUnit = matchOne
        } else {
            selectedUnit = units.first
        }
    }

    func selectDefaultPackItemUnit() {
        let units = availablePackItemUnits
        if let matchOne = units.first(where: { $0.factorToBase == "1" }) {
            selectedPackItemUnit = matchOne
        } else {
            selectedPackItemUnit = units.first
        }
    }

    /// Carga los valores de una marca existente.
    func load(presentation: Presentation) {
        if let count = presentation.packCount, let itemQty = presentation.packItemQuantity {
            quantityText = "\(count)"
            let all = store.data.availableKitchenUnits()
            selectedUnit = all.first(where: { $0.id == "sys.pz" }) ?? all.first(where: { $0.baseUnit == .pz })
            packItemQuantityText = Quantity.format(itemQty).replacingOccurrences(of: ",", with: "")
            selectDefaultPackItemUnit()
        } else {
            quantityText = Quantity.format(presentation.packageQuantity).replacingOccurrences(of: ",", with: "")
            selectDefaultUnit()
            packItemQuantityText = ""
            selectDefaultPackItemUnit()
        }
    }

    func updateBaseUnit(_ newBaseUnit: BaseUnit, conversions newConversions: [IngredientConversion]) {
        self.baseUnit = newBaseUnit
        self.conversions = newConversions
        validateOrResetUnits()
    }

    func updateConversions(_ newConversions: [IngredientConversion]) {
        self.conversions = newConversions
        validateOrResetUnits()
    }

    private func validateOrResetUnits() {
        let available = availableUnits
        if let current = selectedUnit {
            if !available.contains(where: { $0.id == current.id }) {
                selectDefaultUnit()
            }
        } else {
            selectDefaultUnit()
        }

        let packUnits = availablePackItemUnits
        if let currentPack = selectedPackItemUnit {
            if !packUnits.contains(where: { $0.id == currentPack.id }) {
                selectDefaultPackItemUnit()
            }
        } else {
            selectDefaultPackItemUnit()
        }

        if isPiecesMode && packItemQuantityText.isEmpty {
            onEnterPiecesMode()
        }
    }
}

// MARK: - Vista compartida de tamaño del paquete

struct PackageSizeField: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var input: PackageSizeInput
    var isInvalid: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Tamaño del paquete")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.inkPrimary)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: Spacing.sm) {
                    quantityInput
                    unitMenu
                }
            } else {
                HStack(spacing: Spacing.sm) {
                    quantityInput
                    unitMenu
                        .frame(minWidth: 100)
                }
            }

            if let warning = input.piecesWarningText {
                Text(warning)
                    .font(.footnote)
                    .foregroundStyle(.warningText)
                    .padding(.horizontal, Spacing.xs)
            }

            if input.isPiecesMode {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Cada pieza trae")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.inkPrimary)

                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: Spacing.sm) {
                            packItemQuantityInput
                            packItemUnitMenu
                        }
                    } else {
                        HStack(spacing: Spacing.sm) {
                            packItemQuantityInput
                            packItemUnitMenu
                                .frame(minWidth: 100)
                        }
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Por ejemplo, una reja de 24 botes de 900 ml.")
                            .font(.footnote)
                            .foregroundStyle(.inkMuted)

                        if input.isValid, let totalText = input.totalInBaseText {
                            Text("En total: \(totalText)")
                                .font(.footnote)
                                .foregroundStyle(.inkMuted)
                        }
                    }
                    .padding(.horizontal, Spacing.xs)
                }
                .padding(.top, Spacing.xs)
            }
        }
    }

    private var isQuantityInvalidBorder: Bool {
        if isInvalid && Quantity.parse(input.quantityText) == nil {
            return true
        }
        if input.isPiecesMode {
            if isInvalid && input.packCount == nil {
                return true
            }
            if !input.quantityText.isEmpty && !input.isPiecesInteger && Quantity.parse(input.quantityText) != nil {
                return true
            }
        }
        return false
    }

    private var isPackItemQuantityInvalidBorder: Bool {
        if isInvalid && Quantity.parse(input.packItemQuantityText) == nil {
            return true
        }
        return false
    }

    private var quantityInput: some View {
        TextField("1", text: $input.quantityText)
            .keyboardType(.decimalPad)
            .font(.body)
            .foregroundStyle(.inkPrimary)
            .padding(.horizontal, 18)
            .frame(minHeight: 56)
            .background(.surfaceInput, in: .rect(cornerRadius: Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(
                        isQuantityInvalidBorder ? Color.warningText : Color.borderInput,
                        lineWidth: isQuantityInvalidBorder ? 2 : 1.5
                    )
            }
            .accessibilityLabel("Cantidad del paquete")
    }

    private var unitMenu: some View {
        Menu {
            ForEach(input.availableUnits) { unit in
                Button("\(unit.name) (\(unit.abbreviation))") {
                    input.selectUnit(unit)
                }
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Text(input.selectedUnit?.abbreviation ?? "Unidad")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.inkPrimary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.inkMuted)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 56)
            .background(.surfaceInput, in: .rect(cornerRadius: Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(Color.borderInput, lineWidth: 1.5)
            }
        }
        .accessibilityLabel("Unidad: \(input.selectedUnit?.abbreviation ?? "")")
    }

    private var packItemQuantityInput: some View {
        TextField("1", text: $input.packItemQuantityText)
            .keyboardType(.decimalPad)
            .font(.body)
            .foregroundStyle(.inkPrimary)
            .padding(.horizontal, 18)
            .frame(minHeight: 56)
            .background(.surfaceInput, in: .rect(cornerRadius: Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(
                        isPackItemQuantityInvalidBorder ? Color.warningText : Color.borderInput,
                        lineWidth: isPackItemQuantityInvalidBorder ? 2 : 1.5
                    )
            }
            .accessibilityLabel("Cantidad de cada pieza")
    }

    private var packItemUnitMenu: some View {
        Menu {
            ForEach(input.availablePackItemUnits) { unit in
                Button("\(unit.name) (\(unit.abbreviation))") {
                    input.selectedPackItemUnit = unit
                }
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Text(input.selectedPackItemUnit?.abbreviation ?? "Unidad")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.inkPrimary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.inkMuted)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 56)
            .background(.surfaceInput, in: .rect(cornerRadius: Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(Color.borderInput, lineWidth: 1.5)
            }
        }
        .accessibilityLabel("Unidad de cada pieza: \(input.selectedPackItemUnit?.abbreviation ?? "")")
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Leche en modo piezas - Claro") {
    let store = LocalStore.preview()
    let input = PackageSizeInput(
        store: store,
        baseUnit: .ml,
        conversions: [],
        quantityText: "24",
        packItemQuantityText: "900"
    )
    if let pzUnit = store.data.availableKitchenUnits().first(where: { $0.id == "sys.pz" }) {
        input.selectUnit(pzUnit)
    }
    return PackageSizeField(input: input)
        .padding()
}

#Preview("Leche en modo piezas - Letra AX3") {
    let store = LocalStore.preview()
    let input = PackageSizeInput(
        store: store,
        baseUnit: .ml,
        conversions: [],
        quantityText: "24",
        packItemQuantityText: "900"
    )
    if let pzUnit = store.data.availableKitchenUnits().first(where: { $0.id == "sys.pz" }) {
        input.selectUnit(pzUnit)
    }
    return PackageSizeField(input: input)
        .padding()
        .dynamicTypeSize(.accessibility3)
}
#endif
