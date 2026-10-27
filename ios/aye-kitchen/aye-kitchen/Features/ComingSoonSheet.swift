import SwiftUI

/// Hoja provisional para las acciones que todavía no existen. Se reemplaza al implementar cada una.
struct ComingSoonSheet: View {
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: "hammer", description: Text("Todavía no está lista."))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium])
    }
}
