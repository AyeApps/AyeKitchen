// swift-tools-version: 6.0
// KitchenKit: datos y reglas de AyeKitchen sin red ni interfaz.
// La app guarda sus datos en un archivo con el formato de docs/backup-format.md y calcula todo
// aquí (costeo, conversiones, validaciones). Las pruebas corren en la Mac: `swift test`.
import PackageDescription

let package = Package(
    name: "KitchenKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "KitchenDomain", targets: ["KitchenDomain"]),
    ],
    targets: [
        .target(name: "KitchenDomain"),
        .testTarget(
            name: "KitchenDomainTests",
            dependencies: ["KitchenDomain"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
