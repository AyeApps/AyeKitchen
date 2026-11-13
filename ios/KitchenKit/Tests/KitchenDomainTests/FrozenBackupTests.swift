import Foundation
import Testing
@testable import KitchenDomain

/// Respaldos congelados (`Fixtures/backup_*.json`): copias del formato tal como lo tienen guardado los
/// usuarios reales. NUNCA se editan ni se borran; cada cambio de formato agrega uno nuevo.
/// Cada uno debe poder leerse y, al volver a guardarse, conservar cada llave y cada valor.
@Suite("Respaldos congelados: integridad de los datos de usuarios reales")
struct FrozenBackupTests {
    private static func fixtureURLs() throws -> [URL] {
        let dir = try #require(
            Bundle.module.url(forResource: "Fixtures", withExtension: nil)
                ?? Bundle.module.resourceURL
        )
        let urls = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("backup_") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return urls
    }

    @Test("Hay al menos un respaldo congelado")
    func hasFixtures() throws {
        #expect(try !Self.fixtureURLs().isEmpty)
    }

    @Test("Cada respaldo congelado se lee y al guardarse no pierde ni cambia nada")
    func everyFrozenBackupSurvivesRoundTrip() throws {
        for url in try Self.fixtureURLs() {
            let original = try Data(contentsOf: url)
            let decoded = try KitchenCoding.decode(original)
            let reencoded = try KitchenCoding.encode(decoded)

            let before = try JSONSerialization.jsonObject(with: original)
            let after = try JSONSerialization.jsonObject(with: reencoded)
            var problems: [String] = []
            Self.compare(before, after, path: url.lastPathComponent, problems: &problems)
            #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")

            // Y una segunda vuelta queda idéntica a la primera.
            #expect(try KitchenCoding.decode(reencoded) == decoded)
        }
    }

    @Test("El respaldo del 2026-11-13 conserva sus datos clave")
    func knownValues() throws {
        let url = try #require(try Self.fixtureURLs().first { $0.lastPathComponent == "backup_v1_2026-11-13.json" })
        let data = try KitchenCoding.decode(Data(contentsOf: url))
        #expect(data.ingredients.count == 4)
        #expect(data.ingredients.first { $0.id == "ing-borrado" }?.deletedAt != nil)
        let kirkland = try #require(data.presentations.first { $0.id == "pres-kirkland" })
        #expect(kirkland.packCount == 24)
        #expect(kirkland.packItemQuantity == "900")
        #expect(kirkland.packageQuantity == "21600")
        #expect(data.priceRecords.first { $0.presentationId == "pres-kirkland" }?.priceCents == 38900)
        #expect(data.orders.first?.items.count == 2)
        #expect(data.orders.first?.payments.first?.amountCents == 20000)
        #expect(data.recipes.first { $0.id == "rec-pastel" }?.salePriceCents == 45000)
        #expect(data.references.first?.sha256.count == 64)
    }

    /// Todo lo que hay en `before` debe estar igual en `after` (un `null` en `before` equivale a no estar).
    /// `after` puede traer llaves de más (campos nuevos con valor por defecto).
    private static func compare(_ before: Any, _ after: Any?, path: String, problems: inout [String]) {
        switch before {
        case let dict as [String: Any]:
            guard let afterDict = after as? [String: Any] else {
                problems.append("\(path): era un objeto y ya no"); return
            }
            for (key, value) in dict {
                if value is NSNull, afterDict[key] == nil || afterDict[key] is NSNull { continue }
                guard let afterValue = afterDict[key] else {
                    problems.append("\(path).\(key): se perdió"); continue
                }
                compare(value, afterValue, path: "\(path).\(key)", problems: &problems)
            }
        case let array as [Any]:
            guard let afterArray = after as? [Any], afterArray.count == array.count else {
                problems.append("\(path): la lista cambió de tamaño"); return
            }
            for (i, value) in array.enumerated() {
                compare(value, afterArray[i], path: "\(path)[\(i)]", problems: &problems)
            }
        default:
            let a = before as? NSObject
            let b = after as? NSObject
            if a != b {
                problems.append("\(path): \(String(describing: before)) → \(String(describing: after ?? "nada"))")
            }
        }
    }
}
