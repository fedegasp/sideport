import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var devices: DeviceMonitor
    @EnvironmentObject private var ui: UIState

    @State private var search = ""
    @State private var selection = Set<URL>()
    @State private var isImporting = false
    @State private var isChoosingFolder = false
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

    var body: some View {
        Group {
            if library.packages.isEmpty && !library.isScanning {
                EmptyStateView(
                    symbol: "square.stack.3d.down.right",
                    title: "Libreria vuota",
                    message: "Aggiungi i file .ipa che vuoi installare sui tuoi dispositivi. Puoi anche trascinarli qui.",
                    action: ("Importa .ipa…", { isImporting = true })
                )
            } else {
                table
            }
        }
        .navigationTitle("Libreria")
        .navigationSubtitle(subtitle)
        .searchable(text: $search, prompt: "Cerca per nome o bundle ID")
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
            isPresented: $isImporting,
            allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                Task { await library.importPackages(from: urls) }
            }
        }
        .fileImporter(
            isPresented: $isChoosingFolder,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let folder) = result {
                Task { await library.setLibraryURL(folder) }
            }
        }
        .sheet(item: $ui.inspectPackage) { package in
            IPAContentsSheet(package: package)
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
    }

    private var subtitle: String {
        let total = library.packages.reduce(Int64(0)) { $0 + $1.fileSize }
        return "\(library.packages.count) app · \(Format.bytes(total))"
    }

    private var table: some View {
        Table(filtered, selection: $selection) {
            TableColumn("App") { package in
                HStack(spacing: 8) {
                    AppIconView(data: package.iconData, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(package.name).lineLimit(1)
                        Text(package.bundleIdentifier)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .width(min: 220, ideal: 300)

            TableColumn("Versione") { Text($0.versionLabel).monospacedDigit() }
                .width(min: 80, ideal: 110)

            TableColumn("iOS min.") { package in
                Text(package.minimumOSVersion.isEmpty ? "—" : package.minimumOSVersion).monospacedDigit()
            }
            .width(min: 60, ideal: 80)

            TableColumn("Dispositivi") { Text($0.deviceFamilyLabel).foregroundStyle(.secondary) }
                .width(min: 80, ideal: 110)

            TableColumn("Firma") { Text($0.signing.rawValue).foregroundStyle(.secondary) }
                .width(min: 90, ideal: 130)

            // L'azione vive nell'ultima colonna invece che in una colonna
            // dedicata: SwiftUI distribuisce la larghezza fra le colonne
            // esistenti e una settima finirebbe fuori dal bordo della finestra.
            TableColumn("Dimensione") { package in
                HStack(spacing: 10) {
                    Text(Format.bytes(package.fileSize)).monospacedDigit()
                    Spacer(minLength: 8)
                    Button {
                        ui.inspectPackage = package
                    } label: {
                        Label("Ispeziona", systemImage: "list.bullet.indent")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Mostra il contenuto dell'archivio .ipa")
                }
            }
            .width(min: 180, ideal: 210)
        }
        .contextMenu(forSelectionType: URL.self) { urls in
            let packages = library.packages.filter { urls.contains($0.url) }
            Button("Installa su…") { ui.installSheet = .init(packages: packages) }
                .disabled(packages.isEmpty || readyDevices.isEmpty)
            Button("Ispeziona contenuto") { ui.inspectPackage = packages.first }
                .disabled(packages.count != 1)
            Button("Mostra nel Finder") { packages.first.map(library.reveal) }
                .disabled(packages.isEmpty)
            Divider()
            Button("Sposta nel cestino", role: .destructive) {
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
                    Text("Analisi archivi…").font(.caption).foregroundStyle(.secondary)
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
                    Label("Installa su…", systemImage: "arrow.down.to.line")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedPackages.isEmpty || readyDevices.isEmpty)
                .help(readyDevices.isEmpty ? "Collega e autorizza un dispositivo" : "Installa le app selezionate")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button { isImporting = true } label: {
                Label("Importa", systemImage: "plus")
            }
            .help("Importa file .ipa nella libreria")

            Button { Task { await library.refresh() } } label: {
                Label("Aggiorna", systemImage: "arrow.clockwise")
            }
            .disabled(library.isScanning)

            Menu {
                Button("Apri cartella libreria") { library.openLibraryFolder() }
                Button("Cambia cartella…") { isChoosingFolder = true }
                Button("Ripristina cartella predefinita") {
                    Task { await library.setLibraryURL(LibraryStore.defaultLibraryURL) }
                }
            } label: {
                Label("Cartella", systemImage: "folder")
            }
        }
    }
}
