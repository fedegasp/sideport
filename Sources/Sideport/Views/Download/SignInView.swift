import SwiftUI

struct SignInView: View {
    @Environment(StoreService.self) private var store

    @State private var email = ""
    @State private var password = ""
    @State private var authCode = ""
    @FocusState private var focus: Field?

    private enum Field { case email, password, code }

    private var awaitingCode: Bool { store.authState == .awaitingAuthCode }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Image(systemName: "person.badge.key")
                        .font(.system(size: 36))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text(.ui("Sign in to the App Store"))
                        .font(.title3.weight(.semibold))
                    Text(.ui("You need the Apple ID credentials that own the apps: only free apps, or apps already purchased with that account, can be downloaded."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 430)
                }

                VStack(spacing: 10) {
                    TextField(text: $email, prompt: Text(.ui("Apple ID"))) { Text(.ui("Apple ID")) }
                        .textContentType(.username)
                        .focused($focus, equals: .email)
                        .disabled(awaitingCode || store.authState.isBusy)
                    SecureField(text: $password, prompt: Text(.ui("Password"))) { Text(.ui("Password")) }
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .disabled(awaitingCode || store.authState.isBusy)
                        .onSubmit(submit)

                    if awaitingCode {
                        VStack(alignment: .leading, spacing: 6) {
                            Divider()
                            Text(.ui("Apple sent a verification code to your devices."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField(text: $authCode, prompt: Text(.ui("6-digit code"))) {
                                Text(.ui("6-digit code"))
                            }
                            .focused($focus, equals: .code)
                                .onSubmit { store.submitAuthCode(authCode) }
                        }
                    }
                }
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .frame(maxWidth: 340)

                if let error = store.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 430)
                }

                HStack(spacing: 10) {
                    if store.authState.isBusy || awaitingCode {
                        Button(.ui("Cancel")) { store.cancelSignIn() }
                    }
                    if awaitingCode {
                        Button(.ui("Verify")) { store.submitAuthCode(authCode) }
                            .buttonStyle(.borderedProminent)
                            .disabled(authCode.trimmingCharacters(in: .whitespaces).count < 4)
                    } else {
                        Button {
                            submit()
                        } label: {
                            if store.authState.isBusy {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text(.ui("Signing in…"))
                                }
                            } else {
                                Text(.ui("Sign in"))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(email.isEmpty || password.isEmpty || store.authState.isBusy)
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(.ui("The password reaches ipatool through a pseudo-terminal, not the command line: it does not appear in `ps` and Sideport never stores it."), systemImage: "lock")
                        Label(.ui("ipatool keeps the session token in the macOS keychain. On first use macOS may ask for permission to access it."), systemImage: "key")
                        Label(.ui("The download uses a private Apple API, the same one iTunes uses: it can change without notice."), systemImage: "info.circle")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(6)
                }
                .frame(maxWidth: 480)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .onAppear { focus = .email }
        .onChange(of: awaitingCode) { _, isAwaiting in
            if isAwaiting { focus = .code }
        }
    }

    private func submit() {
        guard !email.isEmpty, !password.isEmpty else { return }
        Task {
            await store.signIn(email: email, password: password)
            if store.authState.account != nil {
                password = ""
                authCode = ""
            }
        }
    }
}
