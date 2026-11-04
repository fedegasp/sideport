import Foundation
import Observation

/// Rileva i dispositivi raggiungibili e ne mantiene aggiornate le informazioni.
///
/// `usbmuxd` non espone un canale di notifica tramite i tool a riga di comando,
/// quindi si usa polling di `idevice_id`: `-l` elenca i dispositivi via cavo,
/// `-n` quelli visibili in rete. Le informazioni complete di un dispositivo
/// vengono rilette solo quando compare o periodicamente, perche' ogni query
/// apre una sessione lockdownd.
@MainActor
@Observable
final class DeviceMonitor {
    private(set) var devices: [Device] = []
    private(set) var isRefreshing = false
    var lastError: String?

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    private let pollInterval: Duration = .seconds(2)
    private let detailRefreshEveryTicks = 8
    /// In rete ogni sessione lockdownd costa molto di piu' che via cavo, quindi
    /// i dettagli si rileggono molto piu' di rado.
    private let networkDetailRefreshEveryTicks = 30
    @ObservationIgnored private var tickCount = 0

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: self?.pollInterval ?? .seconds(2))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refreshNow() async {
        tickCount = 0
        await tick(forceDetails: true)
    }

    // MARK: - Polling

    private func tick(forceDetails: Bool = false) async {
        guard let tool = ToolLocator.shared.url(for: .ideviceID) else {
            lastError = ToolError.missing(.ideviceID).localizedDescription
            return
        }

        guard let usb = await listUDIDs(tool, flag: "-l") else { return }
        // Un `-n` fallito non e' un errore da mostrare: l'USB funziona lo stesso
        // e la rete e' un extra che dipende da come e' configurato il dispositivo.
        let network = await listUDIDs(tool, flag: "-n", reportingErrors: false) ?? []
        lastError = nil

        let discovered = Self.merge(usb: usb, network: network)
        let reachable = Set(discovered.map(\.udid))

        // Rimuove i dispositivi scollegati, mantiene l'ordine di connessione.
        devices.removeAll { !reachable.contains($0.udid) }

        let known = Set(devices.map(\.udid))
        // Un dispositivo che passa dal cavo al Wi-Fi (o viceversa) va riletto:
        // cambia il flag con cui lo si raggiunge.
        var switchedTransport: Set<String> = []
        for entry in discovered {
            if known.contains(entry.udid) {
                update(udid: entry.udid) { device in
                    guard device.transport != entry.transport else { return }
                    device.transport = entry.transport
                    switchedTransport.insert(entry.udid)
                }
            } else {
                devices.append(Device(udid: entry.udid, transport: entry.transport))
            }
        }

        tickCount += 1
        let refreshUSB = forceDetails || tickCount % detailRefreshEveryTicks == 1
        let refreshNetwork = forceDetails || tickCount % networkDetailRefreshEveryTicks == 1

        for entry in discovered {
            let isNew = !known.contains(entry.udid)
            let periodic = entry.transport == .network ? refreshNetwork : refreshUSB
            // Un dispositivo non pronto si riprova a ogni giro via cavo. In rete
            // ogni tentativo fallito e' lento, ma aspettare il giro completo
            // lascerebbe un errore momentaneo sullo schermo per un minuto.
            let isReady = devices.first { $0.udid == entry.udid }?.isReady ?? false
            let retryUnready = !isReady && (entry.transport == .usb || refreshUSB)
            if isNew || switchedTransport.contains(entry.udid) || periodic || retryUnready {
                await loadDetails(udid: entry.udid, transport: entry.transport)
            }
        }
    }

    /// UDID elencati da `idevice_id` con il flag dato, `nil` se il tool fallisce.
    private func listUDIDs(_ tool: URL, flag: String, reportingErrors: Bool = true) async -> [String]? {
        do {
            let result = try await ProcessRunner.run(tool, [flag])
            guard result.succeeded else {
                if reportingErrors { lastError = result.failureMessage }
                return nil
            }
            return result.stdout
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        } catch {
            if reportingErrors { lastError = error.localizedDescription }
            return nil
        }
    }

    struct Discovered: Equatable {
        let udid: String
        let transport: Device.Transport
    }

    /// Unisce le due liste di `idevice_id`. Un dispositivo raggiungibile in
    /// entrambi i modi resta sul cavo: e' piu' veloce e non si addormenta.
    /// Interno per i test.
    nonisolated static func merge(usb: [String], network: [String]) -> [Discovered] {
        var seen = Set<String>()
        var merged: [Discovered] = []
        for udid in usb where seen.insert(udid).inserted {
            merged.append(Discovered(udid: udid, transport: .usb))
        }
        for udid in network where seen.insert(udid).inserted {
            merged.append(Discovered(udid: udid, transport: .network))
        }
        return merged
    }

    private func loadDetails(udid: String, transport: Device.Transport) async {
        guard let infoTool = ToolLocator.shared.url(for: .ideviceInfo) else { return }
        let lookup = transport.toolArguments

        do {
            let result = try await ProcessRunner.run(infoTool, lookup + ["-u", udid, "-x"])
            guard result.succeeded, let data = PlistParsing.extractPlistData(from: result.stdout) else {
                update(udid: udid) {
                    $0.state = Self.interpretFailure(result.failureMessage, transport: transport)
                }
                return
            }
            let info = try PlistParsing.dictionary(from: data)
            update(udid: udid) { device in
                device.state = .ready
                device.name = info.string("DeviceName") ?? device.name
                device.productType = info.string("ProductType") ?? device.productType
                device.productVersion = info.string("ProductVersion") ?? device.productVersion
                device.buildVersion = info.string("BuildVersion") ?? device.buildVersion
                device.serialNumber = info.string("SerialNumber") ?? device.serialNumber
                device.deviceClass = info.string("DeviceClass") ?? device.deviceClass
            }
        } catch {
            update(udid: udid) { $0.state = .error(error.localizedDescription) }
            return
        }

        await loadDiskUsage(udid: udid, tool: infoTool, lookup: lookup)
        await loadBattery(udid: udid, tool: infoTool, lookup: lookup)
    }

    private func loadDiskUsage(udid: String, tool: URL, lookup: [String]) async {
        guard let result = try? await ProcessRunner.run(tool, lookup + ["-u", udid, "-q", "com.apple.disk_usage", "-x"]),
              result.succeeded,
              let data = PlistParsing.extractPlistData(from: result.stdout),
              let info = try? PlistParsing.dictionary(from: data) else { return }

        update(udid: udid) { device in
            if let total = info.int("TotalDiskCapacity") { device.totalDiskCapacity = Int64(total) }
            if let available = info.int("TotalDataAvailable") { device.availableDiskCapacity = Int64(available) }
        }
    }

    private func loadBattery(udid: String, tool: URL, lookup: [String]) async {
        guard let result = try? await ProcessRunner.run(tool, lookup + ["-u", udid, "-q", "com.apple.mobile.battery", "-x"]),
              result.succeeded,
              let data = PlistParsing.extractPlistData(from: result.stdout),
              let info = try? PlistParsing.dictionary(from: data) else { return }

        update(udid: udid) { device in
            device.batteryLevel = info.int("BatteryCurrentCapacity")
            device.isCharging = info.bool("BatteryIsCharging")
        }
    }

    /// Distingue "non abbinato" da "bloccato con codice": i messaggi di lockdownd
    /// sono l'unico segnale disponibile dalla CLI. Interno per i test.
    nonisolated static func interpretFailure(
        _ message: String,
        transport: Device.Transport
    ) -> Device.ConnectionState {
        let lowered = message.lowercased()
        if lowered.contains("pair") || lowered.contains("trust") || lowered.contains("invaliddata") {
            return .untrusted
        }
        if lowered.contains("passcode") || lowered.contains("locked") {
            return .locked
        }
        // "Mux error" in rete vuol dire che il socket verso il dispositivo non si
        // apre: usbmuxd lo annuncia ancora via Bonjour ma la connessione TCP non
        // arriva. Il messaggio grezzo non aiuta, le cause tipiche si'.
        if transport == .network, lowered.contains("mux error") {
            return .error(String.ui("Cannot reach the device over Wi-Fi: check that it is awake and on the same network, and that Sideport is allowed under System Settings > Privacy & Security > Local Network."))
        }
        return .error(message.isEmpty ? String.ui("Communication with the device failed.") : message)
    }

    private func update(udid: String, _ transform: (inout Device) -> Void) {
        guard let index = devices.firstIndex(where: { $0.udid == udid }) else { return }
        transform(&devices[index])
    }

    // MARK: - Azioni

    /// Avvia l'abbinamento: l'utente deve toccare "Autorizza" sul dispositivo.
    ///
    /// Un dispositivo visto solo in rete non e' abbinabile: lockdownd accetta
    /// il primo abbinamento soltanto via cavo. Il tentativo si fa comunque,
    /// cosi' l'errore di lockdownd arriva all'utente invece di essere inventato.
    func pair(udid: String) async {
        guard let tool = ToolLocator.shared.url(for: .idevicePair) else {
            lastError = ToolError.missing(.idevicePair).localizedDescription
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        let transport = transport(for: udid)
        let result = try? await ProcessRunner.run(tool, transport.toolArguments + ["-u", udid, "pair"])
        if let result, !result.succeeded {
            update(udid: udid) {
                $0.state = Self.interpretFailure(result.failureMessage, transport: transport)
            }
        }
        await loadDetails(udid: udid, transport: transport)
    }

    func rename(udid: String, to newName: String) async throws {
        let tool = try ToolLocator.shared.require(.ideviceName)
        let arguments = transport(for: udid).toolArguments + ["-u", udid, newName]
        try await ProcessRunner.runChecked(tool, arguments, toolName: "idevicename")
        update(udid: udid) { $0.name = newName }
    }

    func device(withUDID udid: String) -> Device? {
        devices.first { $0.udid == udid }
    }

    /// Dispositivi sconosciuti si assumono via cavo: e' il comportamento dei
    /// tool senza `-n`.
    func transport(for udid: String) -> Device.Transport {
        device(withUDID: udid)?.transport ?? .usb
    }
}
