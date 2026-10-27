import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(DeviceMonitor.self) private var devices
    @Environment(UIState.self) private var ui

    private enum ImportMode {
        case none, ipa, folder

        var isPresented: Bool {
            get { self != .none }
            set { if !newValue { self = .none } }
        }

        var contentTypes: [UTType] {
            switch self {
            case .ipa: [UTType(filenameExtension: "ipa") ?? .data]
            case .folder: [.folder]
            case .none: []
            }
        }
    }

    @State private var search = ""
    @State private var selection = Set<URL>()
    @State private var importMode: ImportMode = .none
    @State private var isTargeted = false

    private var filtered: [IPAPackage] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return library.packages }
        return library.packages.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedPackages: [IPAPackage] {
        library.packages.filter { selection.contains($0.url) }
    }

    private var readyDevices: [Device] { devices.devices.filter(\.isReady) }

    /// Due .ipa della stessa app (per esempio l'originale e una rifirmata)
    /// hanno nome, versione e dimensione quasi identici: solo per quelle si
    /// mostra anche il nome del file.
    private var duplicated: Set<String> { IPAPackage.duplicatedBundleIdentifiers(in: library.packages) }

    var body: some View {
        @Bindable var ui = ui

        Group {
            if library.packages.isEmpty && !library.isScanning {
                EmptyStateView(
                    symbol: "square.stack.3d.down.right",
                    title: .ui("Empty library"),
                    message: .ui("Add the .ipa files you want to install on your devices. You can also drag them here."),
                    action: (.ui("Import .ipa…"), { importMode = .ipa })
                )
            } else {
                table
            }
        }
        .navigationTitle(.ui("Library"))
        .navigationSubtitle(subtitle)
        .searchable(text: $search, prompt: Text(.ui("Search by name or bundle ID")))
        .toolbar { toolbarContent }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.tint, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let ipas = urls.filter { $0.pathExtension.lowercased() == "ipa" }
            guard !ipas.isEmpty else { return false }
            Task { await library.importPackages(from: ipas) }
            return true
        } isTargeted: { isTargeted = $0 }
        .fileImporter(
            isPresented: $importMode.isPresented,
            allowedContentTypes: importMode.contentTypes,
            allowsMultipleSelection: importMode == .ipa
        ) { result in
            guard case .success(let urls) = result else { return }
            switch importMode {
            case .ipa:
                Task { await library.importPackages(from: urls) }
            case .folder:
                if let folder = urls.first {
                    Task { await library.setLibraryURL(folder) }
                }
            case .none:
                break
            }
        }
        .sheet(item: $ui.inspectPackage) { package in
            IPAContentsSheet(package: package)
        }
        .sheet(item: $ui.resignPackage) { package in
            ResignSheet(package: package)
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
    }

    private var subtitle: String {
        let total = library.packages.reduce(Int64(0)) { $0 + $1.fileSize }
        return String.ui("\(library.packages.count) apps · \(Format.bytes(total))")
    }

    /// L'identificativo, piu' il nome del file quando non basta a dire quale
    /// delle due .ipa e'.
    private func subtitle(for package: IPAPackage) -> String {
        guard duplicated.contains(package.bundleIdentifier) else { return package.bundleIdentifier }
        return String.ui("\(package.bundleIdentifier) · \(package.url.lastPathComponent)")
    }

    private var table: some View {
        Table(filtered, selection: $selection) {
            TableColumn(.ui("App")) { package in
                HStack(spacing: 8) {
                    AppIconView(data: package.iconData, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(package.name).lineLimit(1)
                        // Una riga sola: nella tabella l'altezza e' uniforme e
                        // una terza riga verrebbe tagliata.
                        Text(subtitle(for: package))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .width(min: 220, ideal: 300)

            TableColumn(.ui("Version")) { Text($0.versionLabel).monospacedDigit() }
                .width(min: 80, ideal: 110)

            TableColumn(.ui("Min. iOS")) { package in
                Text(package.minimumOSVersion.isEmpty ? "—" : package.minimumOSVersion).monospacedDigit()
            }
            .width(min: 60, ideal: 80)

            TableColumn(.ui("Devices")) { Text($0.deviceFamilyLabel).foregroundStyle(.secondary) }
                .width(min: 80, ideal: 110)

            TableColumn(.ui("Signature")) { package in
                VStack(alignment: .leading, spacing: 1) {
                    Text(package.signatureLabel).foregroundStyle(.secondary)
                    if let signer = package.signature?.signerLabel {
                        Text(signer)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(Text(signer))
                    }
                }
            }
            .width(min: 110, ideal: 170)

            // L'azione vive nell'ultima colonna invece che in una colonna
            // dedicata: SwiftUI distribuisce la larghezza fra le colonne
            // esistenti e una settima finirebbe fuori dal bordo della finestra.
            TableColumn(.ui("Size")) { package in
                HStack(spacing: 10) {
                    Text(Format.bytes(package.fileSize)).monospacedDigit()
                    Spacer(minLength: 8)
                    Button {
                        ui.inspectPackage = package
                    } label: {
                        Label(.ui("Inspect"), systemImage: "list.bullet.indent")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(Text(.ui("Show the contents of the .ipa archive")))
                }
            }
            .width(min: 180, ideal: 210)
        }
        .contextMenu(forSelectionType: URL.self) { urls in
            let packages = library.packages.filter { urls.contains($0.url) }
            Button(.ui("Install on…")) { ui.installSheet = .init(packages: packages) }
                .disabled(packages.isEmpty || readyDevices.isEmpty)
            Button(.ui("Inspect contents")) { ui.inspectPackage = packages.first }
                .disabled(packages.count != 1)
            // Una copia dell'App Store e' cifrata con FairPlay: rifirmarla non
            // la rende installabile altrove.
            Button(.ui("Re-sign…")) { ui.resignPackage = packages.first }
                .disabled(packages.count != 1 || packages.first?.signing == .appStore)
            Button(.ui("Show in Finder")) { packages.first.map(library.reveal) }
                .disabled(packages.isEmpty)
            Divider()
            Button(.ui("Move to Trash"), role: .destructive) {
                Task { for package in packages { await library.delete(package) } }
            }
            .disabled(packages.isEmpty)
        } primaryAction: { urls in
            let packages = library.packages.filter { urls.contains($0.url) }
            guard !packages.isEmpty, !readyDevices.isEmpty else { return }
            ui.installSheet = .init(packages: packages)
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        if !library.packages.isEmpty {
            HStack(spacing: 12) {
                if library.isScanning {
                    ProgressView().controlSize(.small)
                    Text(.ui("Scanning archives…")).font(.caption).foregroundStyle(.secondary)
                } else if let error = library.lastError {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).font(.caption).lineLimit(2).foregroundStyle(.secondary)
                } else {
                    Text(library.libraryURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button {
                    ui.installSheet = .init(packages: selectedPackages)
                } label: {
                    Label(.ui("Install on…"), systemImage: "arrow.down.to.line")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedPackages.isEmpty || readyDevices.isEmpty)
                .help(Text(readyDevices.isEmpty
                           ? .ui("Connect and trust a device")
                           : .ui("Install the selected apps")))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button { importMode = .ipa } label: {
                Label(.ui("Import"), systemImage: "plus")
            }
            .help(Text(.ui("Import .ipa files into the library")))

            Button { Task { await library.refresh() } } label: {
                Label(.ui("Refresh"), systemImage: "arrow.clockwise")
            }
            .disabled(library.isScanning)

            Menu {
                Button(.ui("Open library folder")) { library.openLibraryFolder() }
                Button(.ui("Change folder…")) { importMode = .folder }
                Button(.ui("Restore default folder")) {
                    Task { await library.setLibraryURL(LibraryStore.defaultLibraryURL) }
                }
            } label: {
                Label(.ui("Folder"), systemImage: "folder")
            }
        }
    }
}
