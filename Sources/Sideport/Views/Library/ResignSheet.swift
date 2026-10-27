import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Avanzamento della rifirma: `IPAResigner` riferisce da un task di sfondo e
/// una classe isolata al main actor evita di catturare la vista nel callback.
@MainActor
@Observable
final class ResignProgress {
    var text = ""
}

/// Rifirma di una .ipa con un'identita' del portachiavi e un profilo di
/// provisioning, per installarla su dispositivi che la firma originale non
/// copre.
///
/// I controlli di compatibilita' stanno davanti al pulsante invece che dopo:
/// una firma sbagliata si scopre solo al momento dell'installazione, con un
/// `ApplicationVerificationFailed` che non dice cosa manca.
struct ResignSheet: View {
    let package: IPAPackage

    @Environment(LibraryStore.self) private var library
    @Environment(DeviceMonitor.self) private var devices
    @Environment(\.dismiss) private var dismiss

    @State private var identities: [SigningIdentity] = []
    @State private var profiles: [ProvisioningProfile] = []
    @State private var identity: SigningIdentity?
    @State private var profile: ProvisioningProfile?
    @State private var nestedIdentifiers: [String] = []
    @State private var fairPlay = false
    @State private var useProfileIdentifier = true
    @State private var changeVersion = false
    @State private var shortVersion = ""
    @State private var buildVersion = ""
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var isChoosingProfile = false
    @State private var progress = ResignProgress()
    @State private var created: URL?
    @State private var error: String?

    private struct Check: Identifiable {
        enum State { case ok, warning, failure }
        let id = UUID()
        let state: State
        let text: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 560, height: 480)
        .task { await load() }
        .fileImporter(
            isPresented: $isChoosingProfile,
            allowedContentTypes: [UTType(filenameExtension: "mobileprovision") ?? .data]
        ) { result in
            guard case .success(let url) = result else { return }
            add(profileAt: url)
        }
    }

    // MARK: - Intestazione

    private var header: some View {
        HStack(spacing: 10) {
            AppIconView(data: package.iconData, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(.ui("Re-sign \(package.name)")).font(.headline).lineLimit(1)
                Text(.ui("\(package.bundleIdentifier) · \(package.versionLabel)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
        }
        .padding(16)
    }

    // MARK: - Corpo

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let created {
            EmptyStateView(
                symbol: "checkmark.seal",
                title: .ui("Re-signed archive ready"),
                message: .ui("“\(created.lastPathComponent)” is in the library: install it from there.")
            )
        } else if fairPlay {
            EmptyStateView(
                symbol: "lock.slash",
                title: .ui("This .ipa cannot be re-signed"),
                message: .ui("The binary is encrypted with FairPlay: it only runs on devices signed in with the Apple ID that downloaded it. Re-signing would change the signature but not the encryption.")
            )
        } else if identities.isEmpty {
            EmptyStateView(
                symbol: "key",
                title: .ui("No signing identity"),
                message: .ui("Add an Apple Development or Apple Distribution certificate to the keychain, for example from Xcode under Settings › Accounts.")
            )
        } else if profiles.isEmpty {
            EmptyStateView(
                symbol: "doc.badge.gearshape",
                title: .ui("No provisioning profile"),
                message: .ui("Install a profile with Xcode, or choose a .mobileprovision file."),
                action: (.ui("Choose a profile…"), { isChoosingProfile = true })
            )
        } else {
            ScrollView { form.padding(16) }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(.ui("Signing identity")).font(.subheadline).foregroundStyle(.secondary)
                Picker(selection: $identity) {
                    ForEach(identities) { candidate in
                        Text(candidate.name).tag(Optional(candidate))
                    }
                } label: {
                    EmptyView()
                }
                .labelsHidden()
                .disabled(isWorking)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(.ui("Provisioning profile")).font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button(.ui("Choose a file…")) { isChoosingProfile = true }
                        .buttonStyle(.link)
                        .disabled(isWorking)
                }
                Picker(selection: $profile) {
                    ForEach(profiles) { candidate in
                        Text(label(for: candidate)).tag(Optional(candidate))
                    }
                } label: {
                    EmptyView()
                }
                .labelsHidden()
                .disabled(isWorking)
                .onChange(of: profile) { _, _ in alignIdentityToProfile() }

                if let profile {
                    Text(profile.teamLabel ?? profile.applicationIdentifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if canRenameBundle {
                Toggle(isOn: $useProfileIdentifier) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(.ui("Use the identifier from the profile"))
                        Text(.ui("The app is installed as \(profile?.bundlePattern ?? "") and does not replace the original one on the device."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(isWorking)
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $changeVersion) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(.ui("Change the version number"))
                        Text(.ui("The device shows this number and tells two installs of the same app apart by it."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if changeVersion {
                    HStack(alignment: .top, spacing: 10) {
                        versionField(.ui("Version"), text: $shortVersion)
                        versionField(.ui("Build"), text: $buildVersion)
                        Spacer(minLength: 0)
                    }
                }
            }
            .disabled(isWorking)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                ForEach(checks) { check in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: symbol(for: check.state))
                            .foregroundStyle(tint(for: check.state))
                            .accessibilityHidden(true)
                        Text(check.text).font(.callout)
                        Spacer(minLength: 0)
                    }
                }
            }

            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }

    private func versionField(
        _ title: LocalizedStringResource,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
        }
    }

    // MARK: - Pulsanti

    private var footer: some View {
        HStack(spacing: 10) {
            if isWorking {
                ProgressView().controlSize(.small)
                Text(progress.text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            } else if created != nil {
                Button(.ui("Show in Finder")) {
                    if let created { NSWorkspace.shared.activateFileViewerSelecting([created]) }
                }
            }

            Spacer()

            if created == nil {
                Button(.ui("Cancel"), role: .cancel) { dismiss() }
                    .disabled(isWorking)
                Button(.ui("Re-sign")) { Task { await resign() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canResign)
            } else {
                Button(.ui("Close")) { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }

    // MARK: - Controlli

    /// L'identificativo che l'app avra' dopo la firma.
    private var targetBundleIdentifier: String {
        guard let profile, !profile.covers(bundleIdentifier: package.bundleIdentifier) else {
            return package.bundleIdentifier
        }
        return canRenameBundle && useProfileIdentifier ? profile.bundlePattern : package.bundleIdentifier
    }

    /// La versione che l'app dichiarera' dopo la firma.
    private var targetVersionLabel: String {
        if buildVersion.isEmpty || buildVersion == shortVersion { return shortVersion }
        return "\(shortVersion) (\(buildVersion))"
    }

    /// Cifre separate da punti, come le vuole `CFBundleVersion`: una versione
    /// fuori formato passa la firma e fa fallire l'installazione.
    private func isValidVersion(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count <= 4 && parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isASCII && $0.isNumber }
        }
    }

    /// Rinominare ha senso solo con un profilo che vale per una sola app e che
    /// non copre gia' quella in mano.
    private var canRenameBundle: Bool {
        guard let profile else { return false }
        return !profile.isWildcard && !profile.covers(bundleIdentifier: package.bundleIdentifier)
    }

    /// Le estensioni restano prefissate dall'identificativo dell'app, quindi
    /// seguono la rinomina.
    private var targetNestedIdentifiers: [String] {
        nestedIdentifiers.map { identifier in
            identifier.hasPrefix(package.bundleIdentifier + ".")
                ? targetBundleIdentifier + identifier.dropFirst(package.bundleIdentifier.count)
                : identifier
        }
    }

    /// Per le estensioni che il profilo dell'app non copre si cerca fra quelli
    /// installati: con i profili espliciti ogni bundle ne vuole uno suo, e
    /// chi rifirma la propria app di solito li ha tutti.
    private var extensionProfiles: [String: ProvisioningProfile] {
        guard let main = profile else { return [:] }
        var result: [String: ProvisioningProfile] = [:]
        for identifier in targetNestedIdentifiers where !main.covers(bundleIdentifier: identifier) {
            let candidates = profiles.filter { candidate in
                candidate.covers(bundleIdentifier: identifier)
                    && !candidate.isExpired
                    && (identity.map(candidate.includes(identity:)) ?? true)
            }
            guard let best = candidates.first(where: { $0.teamIdentifier == main.teamIdentifier })
                ?? candidates.first else { continue }
            result[identifier] = best
        }
        return result
    }

    private var checks: [Check] {
        guard let profile else { return [] }
        var result: [Check] = []

        let covered = profile.covers(bundleIdentifier: targetBundleIdentifier)
        result.append(Check(
            state: covered ? .ok : .failure,
            text: covered
                ? String.ui("The profile covers \(targetBundleIdentifier)")
                : String.ui("The profile does not cover \(targetBundleIdentifier)")
        ))

        if !targetNestedIdentifiers.isEmpty {
            let borrowed = extensionProfiles
            let uncovered = targetNestedIdentifiers.filter {
                !profile.covers(bundleIdentifier: $0) && borrowed[$0] == nil
            }
            let text: String
            if !uncovered.isEmpty {
                text = String.ui("No profile covers \(uncovered[0]): use a wildcard profile or install one for this extension")
            } else if borrowed.isEmpty {
                text = String.ui("The profile covers the \(targetNestedIdentifiers.count) embedded extensions")
            } else {
                text = String.ui("\(borrowed.count) embedded extensions signed with their own profile")
            }
            result.append(Check(state: uncovered.isEmpty ? .ok : .failure, text: text))
        }

        if changeVersion {
            let valid = isValidVersion(shortVersion) && isValidVersion(buildVersion)
            result.append(Check(
                state: valid ? .ok : .failure,
                text: valid
                    ? String.ui("The app declares version \(targetVersionLabel)")
                    : String.ui("The version must be digits separated by dots, like 1.2.3")
            ))
        }

        if let identity {
            let included = profile.includes(identity: identity)
            result.append(Check(
                state: included ? .ok : .failure,
                text: included
                    ? String.ui("The profile accepts this identity")
                    : String.ui("The profile does not list this identity: pick another pair")
            ))
        }

        if let expiry = profile.expirationDate {
            result.append(Check(
                state: profile.isExpired ? .failure : .ok,
                text: profile.isExpired
                    ? String.ui("Expired on \(Format.day(expiry))")
                    : String.ui("Expires on \(Format.day(expiry))")
            ))
        }

        result.append(deviceCheck(for: profile))
        return result
    }

    /// I profili di sviluppo e ad hoc valgono solo sui dispositivi registrati:
    /// e' il motivo piu' comune per cui l'installazione fallisce.
    private func deviceCheck(for profile: ProvisioningProfile) -> Check {
        if profile.provisionsAllDevices {
            return Check(state: .ok, text: String.ui("In-house profile: valid on any device"))
        }
        let connected = devices.devices.filter(\.isReady)
        guard !connected.isEmpty else {
            return Check(
                state: .warning,
                text: String.ui("\(profile.deviceUDIDs.count) devices registered in the profile")
            )
        }
        let covered = connected.filter { profile.covers(deviceUDID: $0.udid) }
        if covered.count == connected.count {
            return Check(state: .ok, text: String.ui("Covers every connected device"))
        }
        let missing = connected.filter { !profile.covers(deviceUDID: $0.udid) }
        return Check(
            state: .warning,
            text: String.ui("Does not cover \(missing.map(\.displayName).joined(separator: ", "))")
        )
    }

    private var canResign: Bool {
        guard !isWorking, identity != nil, profile != nil else { return false }
        return !checks.contains { $0.state == .failure }
    }

    private func symbol(for state: Check.State) -> String {
        switch state {
        case .ok: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failure: "xmark.octagon.fill"
        }
    }

    private func tint(for state: Check.State) -> Color {
        switch state {
        case .ok: .green
        case .warning: .orange
        case .failure: .red
        }
    }

    private func label(for profile: ProvisioningProfile) -> String {
        profile.isExpired
            ? String.ui("\(profile.name) — \(profile.bundlePattern) (expired)")
            : String.ui("\(profile.name) — \(profile.bundlePattern)")
    }

    // MARK: - Caricamento

    private func load() async {
        // La lettura dei profili tocca decine di file e ne calcola le
        // impronte: fuori dal main actor, o il foglio si apre a scatti.
        async let found = SigningAssets.identities()
        async let installed = Task.detached { SigningAssets.installedProfiles() }.value
        identities = await found
        profiles = await installed

        let entries = (try? await IPAInspector.contents(of: package.url))?.map(\.path) ?? []
        let signature = await IPAInspector.signature(of: package.url, entries: entries)
        fairPlay = signature.isFairPlayProtected
        nestedIdentifiers = await IPAInspector.nestedBundleIdentifiers(of: package.url, entries: entries)
        shortVersion = package.shortVersion
        buildVersion = package.buildVersion

        preselect()
        isLoading = false
    }

    /// Propone la coppia che ha piu' probabilita' di funzionare: un profilo
    /// valido, che copre l'app e che accetta una delle identita' disponibili.
    private func preselect() {
        let usable = profiles.filter { candidate in
            !candidate.isExpired && identities.contains(where: candidate.includes(identity:))
        }
        profile = usable.first { $0.covers(bundleIdentifier: package.bundleIdentifier) }
            ?? usable.first { $0.isWildcard }
            ?? usable.first
            ?? profiles.first
        alignIdentityToProfile()
    }

    private func alignIdentityToProfile() {
        guard let profile else {
            identity = identity ?? identities.first
            return
        }
        if let current = identity, profile.includes(identity: current) { return }
        identity = identities.first(where: profile.includes(identity:)) ?? identities.first
    }

    private func add(profileAt url: URL) {
        guard let parsed = SigningAssets.profile(at: url) else {
            error = String.ui("“\(url.lastPathComponent)” is not a readable provisioning profile.")
            return
        }
        if !profiles.contains(parsed) { profiles.append(parsed) }
        profile = parsed
        alignIdentityToProfile()
    }

    // MARK: - Esecuzione

    private func resign() async {
        guard let identity, let profile else { return }
        isWorking = true
        error = nil
        defer { isWorking = false }

        let progress = progress
        let request = IPAResigner.Request(
            archive: package.url,
            identity: identity,
            profile: profile,
            bundleIdentifier: targetBundleIdentifier,
            destination: destination(),
            extensionProfiles: extensionProfiles,
            shortVersion: changeVersion ? shortVersion : nil,
            buildVersion: changeVersion ? buildVersion : nil
        )
        do {
            let file = try await IPAResigner.resign(request) { text in
                Task { @MainActor in progress.text = text }
            }
            await library.refresh()
            created = file
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Accanto all'originale, con un progressivo se il nome e' gia' preso.
    private func destination() -> URL {
        let base = package.url.deletingPathExtension().lastPathComponent + " (" + String.ui("re-signed") + ")"
        var candidate = library.libraryURL.appending(path: base + ".ipa")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = library.libraryURL.appending(path: "\(base) \(counter).ipa")
            counter += 1
        }
        return candidate
    }
}
