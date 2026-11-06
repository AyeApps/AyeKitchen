import SwiftUI
import UIKit
import KitchenDomain

/// Visor a pantalla completa de imágenes de referencia con carrusel paginado y zoom (Bloque I27).
struct ReferenceViewer: View {
    @Environment(\.dismiss) private var dismiss

    let owner: ReferenceOwner
    let initialReferenceId: String
    private let store: LocalStore
    private let imageResolver: ((String) -> UIImage?)?

    @State private var selectedId: String
    @State private var showingDeleteConfirmation = false
    @State private var deleteErrorMessage: String?

    init(
        owner: ReferenceOwner,
        initialReferenceId: String,
        store: LocalStore = .shared,
        imageResolver: ((String) -> UIImage?)? = nil
    ) {
        self.owner = owner
        self.initialReferenceId = initialReferenceId
        self.store = store
        self.imageResolver = imageResolver
        self._selectedId = State(initialValue: initialReferenceId)
    }

    private var references: [ReferenceImage] {
        store.data.references(of: owner)
    }

    private var currentIndex: Int {
        references.firstIndex(where: { $0.id == selectedId }) ?? 0
    }

    private var titleText: String {
        guard references.count > 1 else { return "" }
        return "\(currentIndex + 1) de \(references.count)"
    }

    private func resolveImage(for id: String) -> UIImage? {
        if let imageResolver {
            return imageResolver(id)
        }
        return ReferenceStore.shared.image(for: id)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.canvasBackground
                    .ignoresSafeArea()

                if references.isEmpty {
                    ContentUnavailableView(
                        "Sin referencias",
                        systemImage: "photo.on.rectangle",
                        description: Text("Ya no quedan referencias para este elemento.")
                    )
                } else {
                    TabView(selection: $selectedId) {
                        ForEach(Array(references.enumerated()), id: \.element.id) { index, ref in
                            ReferencePage(
                                reference: ref,
                                image: resolveImage(for: ref.id)
                            )
                            .tag(ref.id)
                            .accessibilityLabel("Referencia \(index + 1) de \(references.count)")
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: references.count > 1 ? .always : .never))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                }
            }
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Listo") {
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Quitar referencia", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                    .disabled(references.isEmpty)
                    .accessibilityLabel("Opciones de la referencia")
                }
            }
            .confirmationDialog(
                "¿Quitar esta referencia? No cambia nada más.",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Quitar referencia", role: .destructive) {
                    deleteCurrentReference()
                }
                Button("Cancelar", role: .cancel) {}
            }
            .alert(
                "No se pudo quitar la referencia",
                isPresented: Binding(
                    get: { deleteErrorMessage != nil },
                    set: { if !$0 { deleteErrorMessage = nil } }
                )
            ) {
                Button("Entendido", role: .cancel) {}
            } message: {
                if let deleteErrorMessage {
                    Text(deleteErrorMessage)
                }
            }
        }
    }

    private func deleteCurrentReference() {
        let idToDelete = selectedId
        let all = references
        guard let idx = all.firstIndex(where: { $0.id == idToDelete }) else { return }

        let nextId: String?
        if all.count <= 1 {
            nextId = nil
        } else if idx + 1 < all.count {
            nextId = all[idx + 1].id
        } else {
            nextId = all[idx - 1].id
        }

        do {
            try ReferenceStore.shared.remove(idToDelete, from: owner)
            if let nextId {
                selectedId = nextId
            } else {
                dismiss()
            }
        } catch {
            deleteErrorMessage = "No se pudo quitar la referencia. Intenta de nuevo."
        }
    }
}

// MARK: - Página individual con Zoom

private struct ReferencePage: View {
    let reference: ReferenceImage
    let image: UIImage?

    var body: some View {
        Group {
            if let image {
                ZoomableImageView(image: image)
            } else {
                VStack(spacing: Spacing.md) {
                    ProgressView()
                    Text("Cargando imagen...")
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - ZoomableImageView con UIScrollView nativo

@MainActor
private struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> CenteringZoomScrollView {
        let scrollView = CenteringZoomScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 4.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .clear

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        scrollView.addSubview(imageView)
        scrollView.imageView = imageView
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ uiView: CenteringZoomScrollView, context: Context) {
        uiView.imageView?.image = image
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            if scrollView.zoomScale > 1.0 {
                scrollView.setZoomScale(1.0, animated: true)
            } else {
                let point = gesture.location(in: gesture.view)
                let zoomScale: CGFloat = 2.5
                let w = scrollView.bounds.width / zoomScale
                let h = scrollView.bounds.height / zoomScale
                let x = point.x - (w / 2.0)
                let y = point.y - (h / 2.0)
                let rectToZoom = CGRect(x: x, y: y, width: w, height: h)
                scrollView.zoom(to: rectToZoom, animated: true)
            }
        }
    }
}

@MainActor
private final class CenteringZoomScrollView: UIScrollView {
    weak var imageView: UIImageView?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let imageView else { return }

        if zoomScale <= 1.0 {
            imageView.frame = bounds
            contentSize = bounds.size
            return
        }

        var frameToCenter = imageView.frame
        if frameToCenter.size.width < bounds.width {
            frameToCenter.origin.x = (bounds.width - frameToCenter.size.width) / 2
        } else {
            frameToCenter.origin.x = 0
        }
        if frameToCenter.size.height < bounds.height {
            frameToCenter.origin.y = (bounds.height - frameToCenter.size.height) / 2
        } else {
            frameToCenter.origin.y = 0
        }
        imageView.frame = frameToCenter
    }
}

// MARK: - Previews

#if DEBUG
private func makeViewerSampleStore(count: Int) -> LocalStore {
    var data = KitchenData.previewSample
    var refIds: [String] = []
    let now = Date()
    for i in 1...count {
        let id = "sample-ref-\(i)"
        refIds.append(id)
        data.references.append(
            ReferenceImage(
                id: id,
                contentType: "image/jpeg",
                sizeBytes: 2048,
                width: 600,
                height: 600,
                sha256: "sha-\(i)",
                createdAt: now,
                updatedAt: now
            )
        )
    }
    if let idx = data.ingredients.firstIndex(where: { $0.id == "ing-harina" }) {
        data.ingredients[idx].referenceIds = refIds
    }
    return LocalStore.preview(data)
}

private func makeViewerSampleImage(text: String, color: UIColor) -> UIImage {
    let size = CGSize(width: 400, height: 400)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { ctx in
        color.setFill()
        ctx.fill(CGRect(origin: .zero, size: size))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 32),
            .foregroundColor: UIColor.white
        ]
        let str = NSString(string: text)
        let strSize = str.size(withAttributes: attrs)
        let rect = CGRect(
            x: (size.width - strSize.width) / 2,
            y: (size.height - strSize.height) / 2,
            width: strSize.width,
            height: strSize.height
        )
        str.draw(in: rect, withAttributes: attrs)
    }
}

#Preview("Visor con 3 referencias") {
    ReferenceViewer(
        owner: .ingredient("ing-harina"),
        initialReferenceId: "sample-ref-1",
        store: makeViewerSampleStore(count: 3),
        imageResolver: { id in
            makeViewerSampleImage(text: id, color: .systemOrange)
        }
    )
}

#Preview("Visor Letra AX3") {
    ReferenceViewer(
        owner: .ingredient("ing-harina"),
        initialReferenceId: "sample-ref-1",
        store: makeViewerSampleStore(count: 3),
        imageResolver: { id in
            makeViewerSampleImage(text: id, color: .systemOrange)
        }
    )
    .dynamicTypeSize(.accessibility3)
}
#endif
