import SwiftUI

struct DeviceInfoList: View {
    let device: Device
    @Environment(DeviceMonitor.self) private var devices
    @State private var newName = ""
    @State private var isRenaming = false
    @State private var renameError: String?

    var body: some View {
        Form {
            Section("Dispositivo") {
                InfoRow(label: "Nome", value: device.name)
                InfoRow(label: "Modello", value: "\(device.marketingName) (\(device.productType))")
                InfoRow(label: "Numero di serie", value: device.serialNumber)
                InfoRow(label: "UDID", value: device.udid)
            }
            Section("Sistema") {
                InfoRow(label: "Versione", value: device.systemVersionLabel)
                InfoRow(label: "Build", value: device.buildVersion)
                InfoRow(label: "Classe", value: device.deviceClass)
            }
            Section("Archiviazione") {
                InfoRow(label: "Capacita' totale", value: Format.bytes(device.totalDiskCapacity))
                InfoRow(label: "Spazio disponibile", value: Format.bytes(device.availableDiskCapacity))
                InfoRow(label: "Spazio usato", value: Format.bytes(device.usedDiskCapacity))
            }
            Section {
                Button("Rinomina dispositivo…", action: beginRename)
                .disabled(ToolLocator.shared.url(for: .ideviceName) == nil)
            }
        }
        .formStyle(.grouped)
        .alert("Rinomina dispositivo", isPresented: $isRenaming) {
            TextField("Nome", text: $newName)
            Button("Annulla", role: .cancel) {}
            Button("Rinomina", action: rename)
        }
        .alert(
            "Rinomina non riuscita",
            isPresented: Binding(get: { renameError != nil }, set: { if !$0 { renameError = nil } }),
            presenting: renameError
        ) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
    }

    private func beginRename() {
        newName = device.name
        isRenaming = true
    }

    private func rename() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Task {
            do {
                try await devices.rename(udid: device.udid, to: name)
            } catch {
                renameError = error.localizedDescription
            }
        }
    }
}
