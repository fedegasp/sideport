import SwiftUI

struct DeviceInfoList: View {
    let device: Device
    @Environment(DeviceMonitor.self) private var devices
    @State private var newName = ""
    @State private var isRenaming = false
    @State private var renameError: String?

    var body: some View {
        Form {
            Section(.ui("Device")) {
                InfoRow(label: .ui("Name"), value: device.name)
                InfoRow(label: .ui("Model"), value: String.ui("\(device.marketingName) (\(device.productType))"))
                InfoRow(label: .ui("Serial number"), value: device.serialNumber)
                InfoRow(label: .ui("UDID"), value: device.udid)
            }
            Section(.ui("System")) {
                InfoRow(label: .ui("Version"), value: device.systemVersionLabel)
                InfoRow(label: .ui("Build"), value: device.buildVersion)
                InfoRow(label: .ui("Class"), value: device.deviceClass)
            }
            Section(.ui("Storage")) {
                InfoRow(label: .ui("Total capacity"), value: Format.bytes(device.totalDiskCapacity))
                InfoRow(label: .ui("Available space"), value: Format.bytes(device.availableDiskCapacity))
                InfoRow(label: .ui("Used space"), value: Format.bytes(device.usedDiskCapacity))
            }
            Section {
                Button(.ui("Rename device…"), action: beginRename)
                .disabled(ToolLocator.shared.url(for: .ideviceName) == nil)
            }
        }
        .formStyle(.grouped)
        .alert(Text(.ui("Rename device")), isPresented: $isRenaming) {
            TextField(text: $newName, prompt: Text(.ui("Name"))) { Text(.ui("Name")) }
            Button(.ui("Cancel"), role: .cancel) {}
            Button(.ui("Rename"), action: rename)
        }
        .alert(
            Text(.ui("Rename failed")),
            isPresented: Binding(get: { renameError != nil }, set: { if !$0 { renameError = nil } }),
            presenting: renameError
        ) { _ in
            Button(.ui("OK")) {}
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
