import SwiftUI

struct EmptyStateView: View {
    let symbol: String
    let title: LocalizedStringResource
    let action: (title: LocalizedStringResource, handler: () -> Void)?

    /// Il messaggio e' testo dell'interfaccia oppure l'errore grezzo di un tool
    /// esterno, che non passa dal catalogo.
    private let message: Message

    private enum Message {
        case localized(LocalizedStringResource)
        case verbatim(String)
    }

    init(
        symbol: String,
        title: LocalizedStringResource,
        message: LocalizedStringResource,
        action: (title: LocalizedStringResource, handler: () -> Void)? = nil
    ) {
        self.symbol = symbol
        self.title = title
        self.message = .localized(message)
        self.action = action
    }

    init(
        symbol: String,
        title: LocalizedStringResource,
        error: String,
        action: (title: LocalizedStringResource, handler: () -> Void)? = nil
    ) {
        self.symbol = symbol
        self.title = title
        self.message = .verbatim(error)
        self.action = action
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 42))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(title)
                .font(.title3.weight(.semibold))
            messageText
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            if let action {
                Button(action.title, action: action.handler)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var messageText: Text {
        switch message {
        case .localized(let resource): Text(resource)
        case .verbatim(let text): Text(text)
        }
    }
}
