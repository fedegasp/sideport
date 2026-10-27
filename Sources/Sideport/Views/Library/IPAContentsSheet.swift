import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Sfoglia l'interno di un .ipa senza estrarlo: l'elenco delle voci arriva da
/// `unzip -l`, che legge solo l'indice dell'archivio. Gli elementi si estraggono
/// trascinandoli nel Finder oppure dai pulsanti in fondo.
///
/// La selezione delle righe e' gestita a mano: `List(selection:)` non registra i
/// clic quando la lista vive in un foglio presentato dal pannello di dettaglio.
struct IPAContentsSheet: View {
    let package: IPAPackage

    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [IPAEntry] = []
    @State private var nodes: [IPANode] = []
    @State private var index: [String: IPANode] = [:]
    @State private var expanded = Set<String>()
    @State private var selection = Set<String>()
    @State private var selectionAnchor: String?
    @State private var search = ""
    @State private var signature: IPASignature?
    @State private var isResigning = false
    @State private var isLoading = true
    @State private var error: String?

    @State private var pending: PendingExtraction?
    @State private var isChoosingDestination = false
    @State private var isExtracting = false
    @State private var actionError: String?

    private enum PendingExtraction {
        case all
        case entries([IPAEntry])
    }

    private struct Row: Identifiable {
        let node: IPANode
        let depth: Int
        let subtitle: String?
        var id: String { node.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 640, height: 520)
        .task {
            do {
                let found = try await IPAInspector.contents(of: package.url)
                entries = found
                nodes = IPAContents.tree(from: found)
                index = IPAContents.index(nodes)
                expanded = IPAContents.defaultExpansion(in: nodes)
                isLoading = false
                signature = await IPAInspector.signature(of: package.url, entries: found.map(\.path))
            } catch {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
        .sheet(isPresented: $isResigning) {
            ResignSheet(package: package)
        }
        .fileImporter(
            isPresented: $isChoosingDestination,
            allowedContentTypes: [.folder]
        ) { result in
            guard case .success(let folder) = result, let target = pending else { return }
            pending = nil
            Task { await extract(target, into: folder) }
        }
        .alert(
            Text(.ui("Extraction failed")),
            isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } }),
            presenting: actionError
        ) { _ in
            Button(.ui("OK")) {}
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Intestazione

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                AppIconView(data: package.iconData, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(package.name).font(.headline).lineLimit(1)
                    Text(.ui("\(package.bundleIdentifier) · \(package.versionLabel)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.bytes(package.fileSize)).monospacedDigit()
                    summaryText
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            signatureStrip

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField(text: $search, prompt: Text(.ui("Filter by name or path"))) {
                    Text(.ui("Filter by name or path"))
                }
                .textFieldStyle(.plain)
                .labelsHidden()
                if !search.isEmpty {
                    Button(.ui("Clear filter"), systemImage: "xmark.circle.fill", action: clearSearch)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .disabled(isLoading || error != nil)
        }
        .padding(12)
    }

    @ViewBuilder
    private var summaryText: some View {
        if isLoading || error != nil {
            Text(verbatim: "—")
        } else {
            let files = entries.filter { !$0.isDirectory }
            let uncompressed = files.reduce(Int64(0)) { $0 + $1.size }
            Text(.ui("\(files.count) files · \(Format.bytes(uncompressed)) extracted"))
        }
    }

    // MARK: - Firma

    /// Riga compatta fra la descrizione e il filtro: tipo di firma, chi l'ha
    /// emessa e scadenza. I dettagli che non entrano nella riga restano nel
    /// suggerimento al passaggio del mouse.
    @ViewBuilder
    private var signatureStrip: some View {
        if error == nil {
            HStack(spacing: 8) {
                Image(systemName: signature?.kind.symbol ?? "lock.doc")
                    .foregroundStyle(signatureTint)
                    .frame(width: 16)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    if let signature {
                        Text(signature.kind.label).font(.caption.weight(.semibold))
                    } else {
                        Text(.ui("Reading the signature…")).font(.caption.weight(.semibold))
                    }
                    if !signatureDetails.isEmpty {
                        Text(signatureDetails.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 12)

                if let expiry = expiryText {
                    expiry
                        .font(.caption)
                        .foregroundStyle(signature?.isExpired == true ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                }

                Button(.ui("Re-sign…")) { isResigning = true }
                    .controlSize(.small)
                    .disabled(signature == nil || signature?.isFairPlayProtected == true)
                    .help(Text(signature?.isFairPlayProtected == true
                               ? .ui("An App Store copy is encrypted with FairPlay: re-signing does not make it installable elsewhere.")
                               : .ui("Sign the archive again with one of your certificates")))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityElement(children: .combine)
            .help(signatureDetails.joined(separator: " · "))
        }
    }

    private var signatureTint: AnyShapeStyle {
        guard let signature else { return AnyShapeStyle(.secondary) }
        if signature.isExpired || signature.kind == .unsigned { return AnyShapeStyle(.red) }
        return AnyShapeStyle(.tint)
    }

    /// Il certificato di firma e' il dato piu' specifico, quindi apre la riga;
    /// il team lo sostituisce quando il certificato non si legge.
    private var signatureDetails: [String] {
        guard let signature else { return [] }
        var parts: [String] = []
        if let certificate = signature.certificate {
            parts.append(certificate)
        } else if let team = signature.teamLabel {
            parts.append(team)
        }
        // Senza un certificato solo nel profilo non si puo' dire chi ha
        // firmato: il nome sta nel binario, non qui.
        if signature.certificate == nil, signature.certificateCount > 1 {
            parts.append(String.ui("\(signature.certificateCount) certificates allowed"))
        }
        if let seller = signature.seller { parts.append(seller) }
        if let appleID = signature.appleID { parts.append(appleID) }
        if let name = signature.profileName { parts.append(name) }
        if let devices = signature.provisionedDeviceCount {
            parts.append(String.ui("\(devices) registered devices"))
        }
        if signature.isFairPlayProtected { parts.append(String.ui("FairPlay protected")) }
        if !signature.isCodeSigned { parts.append(String.ui("no code signature in the bundle")) }
        return parts
    }

    private var expiryText: Text? {
        guard let signature, let date = signature.expirationDate else { return nil }
        return signature.isExpired
            ? Text(.ui("Expired on \(Format.day(date))"))
            : Text(.ui("Expires on \(Format.day(date))"))
    }

    // MARK: - Elenco

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: 8) {
                ProgressView()
                Text(.ui("Reading the archive…")).foregroundStyle(.secondary).font(.callout)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error {
            EmptyStateView(symbol: "exclamationmark.triangle", title: .ui("Unreadable archive"), error: error)
        } else if rows.isEmpty {
            EmptyStateView(
                symbol: "magnifyingglass",
                title: .ui("No matches"),
                message: .ui("No file in the archive contains “\(search)”.")
            )
        } else {
            List {
                ForEach(rows) { row in
                    rowView(row)
                        .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 8))
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .overlay {
                if isExtracting {
                    ProgressView(.ui("Extracting…"))
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .disabled(isExtracting)
        }
    }

    private func rowView(_ row: Row) -> some View {
        let isSelected = selection.contains(row.id)

        return HStack(spacing: 6) {
            Color.clear.frame(width: CGFloat(row.depth) * 14, height: 1)

            if row.node.isDirectory && row.subtitle == nil {
                let isExpanded = expanded.contains(row.node.id)
                Button {
                    toggle(row.node.id)
                } label: {
                    Label(
                        isExpanded ? .ui("Collapse") : .ui("Expand"),
                        systemImage: isExpanded ? "chevron.down" : "chevron.right"
                    )
                    .labelStyle(.iconOnly)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 12, height: 1)
            }

            Image(systemName: icon(for: row.node))
                .foregroundStyle(row.node.isDirectory ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 16)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.node.name).lineLimit(1).truncationMode(.middle)
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 12)

            Text(Format.bytes(row.node.size))
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear))
        )
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { click(row) }
        .accessibilityActions {
            if row.node.isDirectory && row.subtitle == nil {
                Button(expanded.contains(row.node.id) ? .ui("Collapse") : .ui("Expand")) { toggle(row.node.id) }
            }
        }
        // Gesti simultanei: `.draggable` installa il suo riconoscitore sulla
        // riga e un `onTapGesture` normale glielo ruberebbe, lasciando la riga
        // selezionabile ma non trascinabile.
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            if row.node.isDirectory && row.subtitle == nil { toggle(row.node.id) }
        })
        .simultaneousGesture(TapGesture().onEnded { click(row) })
        .onDrag { dragItem(for: row) }
        .contextMenu {
            let targets = extractionTargets(for: row)
            Button(targets.count == 1 ? .ui("Extract…") : .ui("Extract \(targets.count) items…")) {
                pending = .entries(targets)
                isChoosingDestination = true
            }
            Button(.ui("Copy path")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(row.node.id, forType: .string)
            }
        }
    }

    private func icon(for node: IPANode) -> String {
        guard !node.isDirectory else {
            return node.name.hasSuffix(".app") ? "app.badge" : "folder"
        }
        switch (node.name as NSString).pathExtension.lowercased() {
        case "plist", "strings", "json", "xml": return "doc.text"
        case "png", "jpg", "jpeg", "heic", "pdf", "car": return "photo"
        case "mobileprovision", "sinf", "supp", "der": return "lock.doc"
        case "nib", "storyboardc", "lproj": return "doc.richtext"
        default: return "doc"
        }
    }

    // MARK: - Selezione

    /// Clic semplice, ⌘ per aggiungere o togliere, ⇧ per estendere dall'ultima
    /// riga toccata.
    private func click(_ row: Row) {
        let modifiers = NSEvent.modifierFlags

        if modifiers.contains(.command) {
            if selection.contains(row.id) {
                selection.remove(row.id)
            } else {
                selection.insert(row.id)
            }
            selectionAnchor = row.id
        } else if modifiers.contains(.shift),
                  let anchor = selectionAnchor,
                  let start = rows.firstIndex(where: { $0.id == anchor }),
                  let end = rows.firstIndex(where: { $0.id == row.id }) {
            let range = start <= end ? start...end : end...start
            selection.formUnion(rows[range].map(\.id))
        } else {
            selection = [row.id]
            selectionAnchor = row.id
        }
    }

    // MARK: - Righe visibili

    private var rows: [Row] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard query.isEmpty else { return matches(for: query) }

        var result: [Row] = []
        func append(_ nodes: [IPANode], depth: Int) {
            for node in nodes {
                result.append(Row(node: node, depth: depth, subtitle: nil))
                if node.isDirectory, expanded.contains(node.id), let children = node.children {
                    append(children, depth: depth + 1)
                }
            }
        }
        append(nodes, depth: 0)
        return result
    }

    /// In ricerca l'albero lascia il posto a un elenco piatto di file, con il
    /// percorso completo sotto al nome.
    private func matches(for query: String) -> [Row] {
        entries
            .filter { !$0.isDirectory && $0.path.localizedCaseInsensitiveContains(query) }
            .prefix(500)
            .map { entry in
                Row(
                    node: IPANode(id: entry.path, name: entry.name, isDirectory: false, size: entry.size, children: nil),
                    depth: 0,
                    subtitle: entry.path
                )
            }
    }

    private func clearSearch() {
        search = ""
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
        }
    }

    // MARK: - Estrazione

    /// L'elemento viene estratto in una cartella temporanea quando inizia il
    /// trascinamento, cosi' il Finder riceve un file vero con il nome giusto.
    private func dragItem(for row: Row) -> NSItemProvider {
        guard let url = try? IPAExtractor.extractToTemporarySync(
            path: row.node.id,
            isDirectory: row.node.isDirectory,
            from: package.url
        ) else { return NSItemProvider() }
        // Si passa l'URL del file gia' estratto (`public.file-url`): il Finder
        // copia l'elemento con il suo nome, cartelle comprese.
        let provider = NSItemProvider(item: url as NSURL, typeIdentifier: UTType.fileURL.identifier)
        provider.suggestedName = row.node.name
        return provider
    }

    /// Il menu contestuale agisce sull'intera selezione solo se la riga ne fa
    /// parte, come nel Finder.
    private func extractionTargets(for row: Row) -> [IPAEntry] {
        guard selection.contains(row.id), selection.count > 1 else {
            return [entry(for: row.node)]
        }
        return selectedEntries
    }

    private var selectedEntries: [IPAEntry] {
        selection.compactMap { id in
            if let node = index[id] { return entry(for: node) }
            return entries.first { $0.path == id }
        }
    }

    private func entry(for node: IPANode) -> IPAEntry {
        IPAEntry(path: node.id, size: node.size, isDirectory: node.isDirectory)
    }

    private func extract(_ target: PendingExtraction, into folder: URL) async {
        isExtracting = true
        defer { isExtracting = false }
        do {
            switch target {
            case .all:
                let destination = try await IPAExtractor.extractAll(from: package.url, to: folder)
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            case .entries(let entries):
                let extracted = try await IPAExtractor.extract(entries, from: package.url, to: folder)
                NSWorkspace.shared.activateFileViewerSelecting(extracted.isEmpty ? [folder] : extracted)
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: - Pulsanti

    private var footer: some View {
        VStack(spacing: 6) {
            Text(selectionHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Button(.ui("Extract all…")) {
                    pending = .all
                    isChoosingDestination = true
                }
                .disabled(isLoading || error != nil || isExtracting)

                Button(.ui("Extract selection…")) {
                    pending = .entries(selectedEntries)
                    isChoosingDestination = true
                }
                .disabled(selection.isEmpty || isExtracting)

                Button(.ui("Show in Finder")) { library.reveal(package) }

                Spacer()

                Button(.ui("Close")) { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
    }

    private var selectionHint: LocalizedStringResource {
        selection.isEmpty
            ? .ui("Drag an item to the Finder to extract it, or select more than one with ⌘ or ⇧.")
            : .ui("\(selection.count) items selected.")
    }
}
