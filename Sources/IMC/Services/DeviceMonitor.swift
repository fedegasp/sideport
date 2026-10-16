import Foundation
import Combine

/// Rileva i dispositivi collegati via USB e ne mantiene aggiornate le informazioni.
///
/// `usbmuxd` non espone un canale di notifica tramite i tool a riga di comando,
/// quindi si usa polling di `idevice_id -l`. Le informazioni complete di un
/// dispositivo vengono rilette solo quando compare o periodicamente, perche'
/// ogni query apre una sessione lockdownd.
@MainActor
final class DeviceMonitor: ObservableObject {
    @Published private(set) var devices: [Device] = []
    @Published private(set) var isRefreshing = false
    @Published var lastError: String?

    private var pollTask: Task<Void, Never>?
    private let pollInterval: Duration = .seconds(2)
    private let detailRefreshEveryTicks = 8
    private var tickCount = 0

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

        let connected: [String]
        do {
            let result = try await ProcessRunner.run(tool, ["-l"])
            guard result.succeeded else {
                lastError = result.failureMessage
                return
            }
            connected = result.stdout
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            return
        }

        // Rimuove i dispositivi scollegati, mantiene l'ordine di connessione.
        devices.removeAll { !connected.contains($0.udid) }

        let known = Set(devices.map(\.udid))
        let newUDIDs = connected.filter { !known.contains($0) }
        for udid in newUDIDs {
            devices.append(Device(udid: udid))
        }

        tickCount += 1
        let refreshDetails = forceDetails || tickCount % detailRefreshEveryTicks == 1

        for udid in connected {
            let needsLoad = newUDIDs.contains(udid)
                || refreshDetails
                || !(devices.first { $0.udid == udid }?.isReady ?? false)
            if needsLoad {
                await loadDetails(udid: udid)
            }
        }
    }

    private func loadDetails(udid: String) async {
        guard let infoTool = ToolLocator.shared.url(for: .ideviceInfo) else { return }

        do {
            let result = try await ProcessRunner.run(infoTool, ["-u", udid, "-x"])
            guard result.succeeded, let data = PlistParsing.extractPlistData(from: result.stdout) else {
                update(udid: udid) { $0.state = Self.interpretFailure(result.failureMessage) }
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

        await loadDiskUsage(udid: udid, tool: infoTool)
        await loadBattery(udid: udid, tool: infoTool)
    }

    private func loadDiskUsage(udid: String, tool: URL) async {
        guard let result = try? await ProcessRunner.run(tool, ["-u", udid, "-q", "com.apple.disk_usage", "-x"]),
              result.succeeded,
              let data = PlistParsing.extractPlistData(from: result.stdout),
              let info = try? PlistParsing.dictionary(from: data) else { return }

        update(udid: udid) { device in
            if let total = info.int("TotalDiskCapacity") { device.totalDiskCapacity = Int64(total) }
            if let available = info.int("TotalDataAvailable") { device.availableDiskCapacity = Int64(available) }
        }
    }

    private func loadBattery(udid: String, tool: URL) async {
        guard let result = try? await ProcessRunner.run(tool, ["-u", udid, "-q", "com.apple.mobile.battery", "-x"]),
              result.succeeded,
              let data = PlistParsing.extractPlistData(from: result.stdout),
              let info = try? PlistParsing.dictionary(from: data) else { return }

        update(udid: udid) { device in
            device.batteryLevel = info.int("BatteryCurrentCapacity")
            device.isCharging = info.bool("BatteryIsCharging")
        }
    }

    /// Distingue "non abbinato" da "bloccato con codice": i messaggi di lockdownd
    /// sono l'unico segnale disponibile dalla CLI.
    private static func interpretFailure(_ message: String) -> Device.ConnectionState {
        let lowered = message.lowercased()
        if lowered.contains("pair") || lowered.contains("trust") || lowered.contains("invaliddata") {
            return .untrusted
        }
        if lowered.contains("passcode") || lowered.contains("locked") {
            return .locked
        }
        return .error(message.isEmpty ? "Comunicazione con il dispositivo fallita." : message)
    }

    private func update(udid: String, _ transform: (inout Device) -> Void) {
        guard let index = devices.firstIndex(where: { $0.udid == udid }) else { return }
        transform(&devices[index])
    }

    // MARK: - Azioni

    /// Avvia l'abbinamento: l'utente deve toccare "Autorizza" sul dispositivo.
    func pair(udid: String) async {
        guard let tool = ToolLocator.shared.url(for: .idevicePair) else {
            lastError = ToolError.missing(.idevicePair).localizedDescription
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        let result = try? await ProcessRunner.run(tool, ["-u", udid, "pair"])
        if let result, !result.succeeded {
            update(udid: udid) { $0.state = Self.interpretFailure(result.failureMessage) }
        }
        await loadDetails(udid: udid)
    }

    func rename(udid: String, to newName: String) async throws {
        let tool = try ToolLocator.shared.require(.ideviceName)
        try await ProcessRunner.runChecked(tool, ["-u", udid, newName], toolName: "idevicename")
        update(udid: udid) { $0.name = newName }
    }

    func device(withUDID udid: String) -> Device? {
        devices.first { $0.udid == udid }
    }
}
