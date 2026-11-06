import PhotosUI
import SwiftUI
import UIKit
import KitchenDomain

/// Sección discreta de imágenes de referencia al final del detalle de un recurso (Bloque I27).
struct ReferencesSection: View {
    let owner: ReferenceOwner
    var showsTitle: Bool = true
    private let store: LocalStore
    private let imageResolver: ((String) -> UIImage?)?

    @ScaledMetric(relativeTo: .body) private var thumbnailSize: CGFloat = 68

    @State private var pendingCount = 0
    @State private var errorMessage: String?
    @State private var isCameraPresented = false
    @State private var isPhotosPickerPresented = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var activeViewerReferenceId: String?

    init(
        owner: ReferenceOwner,
        showsTitle: Bool = true,
        store: LocalStore = .shared,
        imageResolver: ((String) -> UIImage?)? = nil
    ) {
        self.owner = owner
        self.showsTitle = showsTitle
        self.store = store
        self.imageResolver = imageResolver
    }

    private var references: [ReferenceImage] {
        store.data.references(of: owner)
    }

    private var remainingSlots: Int {
        max(1, 5 - (references.count + pendingCount))
    }

    private func resolveImage(for id: String) -> UIImage? {
        if let imageResolver {
            return imageResolver(id)
        }
        return ReferenceStore.shared.image(for: id)
    }

    var body: some View {
        Group {
            if showsTitle {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Referencias")
                        .sectionTitleStyle()
                    sectionBody
                }
            } else {
                sectionBody
            }
        }
        .photosPicker(
            isPresented: $isPhotosPickerPresented,
            selection: $selectedPhotos,
            maxSelectionCount: remainingSlots,
            matching: .images
        )
        .onChange(of: selectedPhotos) { _, newPhotos in
            guard !newPhotos.isEmpty else { return }
            let items = newPhotos
            selectedPhotos = []
            processSelectedPhotos(items)
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraPicker { image in
                processCameraCapture(image)
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: Binding(
            get: { activeViewerReferenceId.map { ViewerTarget(id: $0) } },
            set: { activeViewerReferenceId = $0?.id }
        )) { target in
            ReferenceViewer(
                owner: owner,
                initialReferenceId: target.id,
                store: store,
                imageResolver: imageResolver
            )
        }
        .alert(
            "No se pudo guardar la referencia",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("Entendido", role: .cancel) {}
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
    }

    @ViewBuilder
    private var sectionBody: some View {
        if references.isEmpty && pendingCount == 0 {
            emptyRow
        } else {
            thumbnailsRow
        }
    }

    // MARK: - Estado sin referencias

    private var emptyRow: some View {
        Menu {
            addMenuOptions
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "plus.circle.fill")
                    .font(.body.weight(.semibold))
                Text("Agregar referencia")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Agregar referencia")
    }

    // MARK: - Fila de miniaturas

    private var thumbnailsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(Array(references.enumerated()), id: \.element.id) { index, ref in
                    Button {
                        activeViewerReferenceId = ref.id
                    } label: {
                        thumbnailView(for: ref)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Referencia \(index + 1) de \(references.count)")
                }

                ForEach(0..<pendingCount, id: \.self) { _ in
                    pendingThumbnailView
                }

                if references.count + pendingCount < 5 {
                    addThumbnailButton
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Miniatura individual

    @ViewBuilder
    private func thumbnailView(for reference: ReferenceImage) -> some View {
        if let img = resolveImage(for: reference.id) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: thumbnailSize, height: thumbnailSize)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.control)
                        .strokeBorder(Color.borderLine, lineWidth: 1)
                }
        } else {
            RoundedRectangle(cornerRadius: Radius.control)
                .fill(.neutralSoft)
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.control)
                        .strokeBorder(Color.borderLine, lineWidth: 1)
                }
                .overlay {
                    Image(systemName: "photo")
                        .font(.body)
                        .foregroundStyle(.inkMuted)
                }
                .frame(width: thumbnailSize, height: thumbnailSize)
        }
    }

    private var pendingThumbnailView: some View {
        RoundedRectangle(cornerRadius: Radius.control)
            .fill(.neutralSoft)
            .overlay {
                RoundedRectangle(cornerRadius: Radius.control)
                    .strokeBorder(Color.borderLine, lineWidth: 1)
            }
            .overlay {
                ProgressView()
            }
            .frame(width: thumbnailSize, height: thumbnailSize)
            .accessibilityLabel("Procesando imagen")
    }

    private var addThumbnailButton: some View {
        Menu {
            addMenuOptions
        } label: {
            RoundedRectangle(cornerRadius: Radius.control)
                .fill(.surfaceCard)
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.control)
                        .strokeBorder(Color.borderLine, lineWidth: 1)
                }
                .overlay {
                    Image(systemName: "plus")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.tint)
                }
                .frame(width: thumbnailSize, height: thumbnailSize)
        }
        .accessibilityLabel("Agregar referencia")
    }

    // MARK: - Menú de adición

    @ViewBuilder
    private var addMenuOptions: some View {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            Button {
                isCameraPresented = true
            } label: {
                Label("Tomar foto", systemImage: "camera")
            }
        }

        Button {
            isPhotosPickerPresented = true
        } label: {
            Label("Elegir de tus fotos", systemImage: "photo.on.rectangle")
        }
    }

    // MARK: - Procesamiento de imágenes

    private func processSelectedPhotos(_ items: [PhotosPickerItem]) {
        Task {
            for item in items {
                pendingCount += 1
                do {
                    if let data = try await item.loadTransferable(type: Data.self) {
                        _ = try await ReferenceStore.shared.add(imageData: data, to: owner)
                    } else {
                        errorMessage = "No pudimos leer la imagen seleccionada. Intenta con otra foto."
                    }
                } catch let error as DomainError {
                    errorMessage = error.detail
                } catch {
                    errorMessage = "No se pudo guardar la referencia. Intenta de nuevo."
                }
                pendingCount -= 1
            }
        }
    }

    private func processCameraCapture(_ image: UIImage) {
        Task {
            pendingCount += 1
            defer { pendingCount -= 1 }
            guard let data = image.jpegData(compressionQuality: 0.85) else {
                errorMessage = "No pudimos procesar la foto tomada."
                return
            }
            do {
                _ = try await ReferenceStore.shared.add(imageData: data, to: owner)
            } catch let error as DomainError {
                errorMessage = error.detail
            } catch {
                errorMessage = "No se pudo guardar la referencia. Intenta de nuevo."
            }
        }
    }
}

private struct ViewerTarget: Identifiable {
    let id: String
}

// MARK: - Previews

#if DEBUG
private func makeSectionSampleStore(count: Int) -> LocalStore {
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

private func makeSectionSampleImage(text: String, color: UIColor) -> UIImage {
    let size = CGSize(width: 300, height: 300)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { ctx in
        color.setFill()
        ctx.fill(CGRect(origin: .zero, size: size))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 26),
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

#Preview("Sin referencias") {
    NavigationStack {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                ReferencesSection(
                    owner: .ingredient("ing-harina"),
                    store: .preview()
                )
            }
            .padding(Spacing.xl)
        }
    }
}

#Preview("Con 3 referencias") {
    NavigationStack {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                ReferencesSection(
                    owner: .ingredient("ing-harina"),
                    store: makeSectionSampleStore(count: 3),
                    imageResolver: { id in
                        makeSectionSampleImage(text: id, color: .systemOrange)
                    }
                )
            }
            .padding(Spacing.xl)
        }
    }
}

#Preview("Con 5 referencias (máximo)") {
    NavigationStack {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                ReferencesSection(
                    owner: .ingredient("ing-harina"),
                    store: makeSectionSampleStore(count: 5),
                    imageResolver: { id in
                        makeSectionSampleImage(text: id, color: .systemOrange)
                    }
                )
            }
            .padding(Spacing.xl)
        }
    }
}

#Preview("Con referencias AX3") {
    NavigationStack {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                ReferencesSection(
                    owner: .ingredient("ing-harina"),
                    store: makeSectionSampleStore(count: 3),
                    imageResolver: { id in
                        makeSectionSampleImage(text: id, color: .systemOrange)
                    }
                )
            }
            .padding(Spacing.xl)
        }
    }
    .dynamicTypeSize(.accessibility3)
}
#endif
