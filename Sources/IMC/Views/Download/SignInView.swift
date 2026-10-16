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
                    Text("Accedi all'App Store")
                        .font(.title3.weight(.semibold))
                    Text("Servono le credenziali dell'Apple ID con cui hai ottenuto le app: si possono scaricare solo app gratuite o gia' acquistate da quell'account.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 430)
                }

                VStack(spacing: 10) {
                    TextField("Apple ID", text: $email)
                        .textContentType(.username)
                        .focused($focus, equals: .email)
                        .disabled(awaitingCode || store.authState.isBusy)
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .disabled(awaitingCode || store.authState.isBusy)
                        .onSubmit(submit)

                    if awaitingCode {
                        VStack(alignment: .leading, spacing: 6) {
                            Divider()
                            Text("Apple ha inviato un codice di verifica ai tuoi dispositivi.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("Codice a 6 cifre", text: $authCode)
                                .focused($focus, equals: .code)
                                .onSubmit { store.submitAuthCode(authCode) }
                        }
                    }
                }
                .textFieldStyle(.roundedBorder)
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
                        Button("Annulla") { store.cancelSignIn() }
                    }
                    if awaitingCode {
                        Button("Verifica") { store.submitAuthCode(authCode) }
                            .buttonStyle(.borderedProminent)
                            .disabled(authCode.trimmingCharacters(in: .whitespaces).count < 4)
                    } else {
                        Button {
                            submit()
                        } label: {
                            if store.authState.isBusy {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Accesso…")
                                }
                            } else {
                                Text("Accedi")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(email.isEmpty || password.isEmpty || store.authState.isBusy)
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("La password viene passata a ipatool attraverso uno pseudo-terminale, non sulla riga di comando: non compare in `ps` e IMC non la salva da nessuna parte.", systemImage: "lock")
                        Label("Il token di sessione lo gestisce ipatool nel portachiavi di macOS. Alla prima richiesta macOS puo' chiedere l'autorizzazione di accesso.", systemImage: "key")
                        Label("Il download usa un'API privata di Apple, la stessa di iTunes: puo' cambiare senza preavviso.", systemImage: "info.circle")
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
