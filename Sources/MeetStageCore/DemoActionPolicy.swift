import Foundation

/// The element an automated demo action would touch, reduced to what the
/// safety policy needs.
public struct DemoPolicyElement: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case button, link, tab, radio, checkbox, menuItem, field, row, cell, other
    }

    public let kind: Kind
    public let label: String
    /// True when the label is data (a row's amounts or names), not a control name.
    /// Only rows and cells can carry data labels.
    public let labelIsData: Bool
    public let isSecure: Bool
    public let isSearchField: Bool
    /// The element sits inside an open dialog, sheet, or alert.
    public let inDialog: Bool
    /// Description, help, identifier, placeholder and container label.
    public let details: [String]

    public init(
        kind: Kind, label: String, labelIsData: Bool = false, isSecure: Bool = false, isSearchField: Bool = false,
        inDialog: Bool = false, details: [String] = []
    ) {
        self.kind = kind
        self.label = label
        self.labelIsData = labelIsData && (kind == .row || kind == .cell)
        self.isSecure = isSecure
        self.isSearchField = isSearchField
        self.inDialog = inDialog
        self.details = details
    }

    var texts: [String] { (labelIsData ? [] : [label]) + details }
}

public enum DemoPolicyAction: Equatable, Sendable {
    case click(DemoPolicyElement)
    case type(field: DemoPolicyElement, text: String, submit: Bool)
    case navigate(URL)
    case pressKey
}

public enum DemoPolicyDecision: Equatable, Sendable {
    case allow
    case needsApproval(String)
    case deny(String)
}

/// Fail-closed rules for actions a demo performs in another app. The scout
/// checks them before every action and replay checks them again on the live
/// element, so an edited or tampered saved demo can't bypass them. Prompts to
/// the model repeat these rules, but the model is never the boundary.
public enum DemoActionPolicy {
    /// Stems that end in a word boundary only where a longer word would be harmless
    /// ("pay" but not "payroll"); the rest also catch "Resend" or "Withdrawals".
    static let destructivePattern =
        #"delete|remove|erase|wipe|reset|discard|trash|sign ?out|log ?out|uninstall|purchase|checkout|place order|transfer|withdraw|swap|stake|approve|confirm|submit|publish|unsubscribe|cancel subscription|\b(pay|buy|send|sign|post|share|invite)\b"#
            + #"|eliminar|borrar|enviar|pagar|comprar|transferir|retirar|confirmar|cerrar sesi[oó]n|excluir|publicar"#
            + #"|supprimer|envoyer|payer|acheter|d[ée]connexion|virement|l[öo]schen|senden|bezahlen|kaufen|abmelden|überweisen"#
            + #"|elimina|cancella|invia|acquista|\b(paga|esci)\b"#

    static let sensitiveFieldPattern =
        #"pass(word|code|phrase)?|contraseña|mot de passe|kennwort|\bpin\b|\botp\b|2fa|one[- ]time|seed|recovery|secret|cvv|cvc|card number|iban|\bssn\b|private key|mnemonic"#

    static let searchPattern =
        #"search|find|filter|look ?up|buscar|busca|rechercher|recherche|suche|suchen|cerca|pesquis|zoek|検索|搜索"#

    /// Controls that only close or decline a dialog.
    static let dismissPattern =
        #"^(cancel|close|dismiss|not now|no thanks|got it|skip|maybe later|back|cancelar|cerrar|ahora no|annuler|fermer|abbrechen|schließen|annulla|chiudi|×|x)$"#

    public static func evaluate(_ action: DemoPolicyAction, prompt: String, startHost: String?, approved: Bool)
        -> DemoPolicyDecision
    {
        let decision = rawDecision(action, prompt: prompt, startHost: startHost)
        if approved, case .needsApproval = decision { return .allow }
        return decision
    }

    private static func rawDecision(_ action: DemoPolicyAction, prompt: String, startHost: String?)
        -> DemoPolicyDecision
    {
        switch action {
        case .pressKey:
            return .allow

        case .click(let element):
            if element.isSecure { return .deny("BetterMeets never clicks password fields.") }
            if let word = firstMatch(destructivePattern, in: element.texts) {
                switch element.kind {
                case .link, .tab, .menuItem:
                    return .needsApproval("Open “\(display(element.label))”? It mentions “\(word)”.")
                default:
                    return .deny(
                        element.label.isEmpty
                            ? "Pointing at this control instead of clicking it; it mentions “\(word)”."
                            : "Pointing at “\(display(element.label))” instead of clicking it.")
                }
            }
            if element.inDialog, element.label.range(of: dismissPattern, options: [.regularExpression, .caseInsensitive]) == nil {
                // A dialog's other buttons usually confirm whatever opened it.
                return .needsApproval("Click “\(display(element.label))” in this dialog?")
            }
            if element.label.isEmpty, element.details.allSatisfy(\.isEmpty) {
                return .needsApproval("Click an unlabelled control?")
            }
            return .allow

        case .type(let field, let text, let submit):
            guard field.kind == .field else { return .deny("Typing only goes into text fields.") }
            if containsControlCharacters(text) {
                return .deny("Typed text can’t contain line breaks, tabs, or control characters.")
            }
            if field.isSecure || firstMatch(sensitiveFieldPattern, in: [field.label] + field.details) != nil {
                return .deny("BetterMeets never types into password, code, or payment fields.")
            }
            if submit, !field.isSearchField, firstMatch(searchPattern, in: [field.label] + field.details) == nil {
                return .needsApproval("Type “\(display(text))” and press Return in “\(display(field.label))”?")
            }
            let typed = normalize(text)
            if typed.isEmpty || !normalize(prompt).contains(typed) {
                return .needsApproval("Type “\(display(text))” into “\(display(field.label))”?")
            }
            return .allow

        case .navigate(let url):
            guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                let host = url.host?.lowercased(), !host.isEmpty, url.user == nil, url.password == nil
            else { return .deny("Only web addresses can be opened.") }
            let bareHost = strippingWWW(host)
            let start = startHost.map { strippingWWW($0.lowercased()) }
            let named = hosts(in: prompt)
            let knownHost =
                bareHost == start || named.contains(bareHost)
                || named.contains { bareHost.hasSuffix("." + $0) }
                || start.map { bareHost.hasSuffix("." + $0) } == true
            let query = url.query.map(normalize) ?? ""
            if !knownHost || (!query.isEmpty && !normalize(prompt).contains(query)) {
                return .needsApproval("Open \(display(host))?")
            }
            return .allow
        }
    }

    public static func isSearchLike(_ texts: [String]) -> Bool {
        firstMatch(searchPattern, in: texts) != nil
    }

    public static func containsControlCharacters(_ text: String) -> Bool {
        let forbidden = CharacterSet.controlCharacters.union(.newlines)
            .union(CharacterSet(charactersIn: "\u{2028}\u{2029}"))
        return text.unicodeScalars.contains { forbidden.contains($0) }
    }

    static func normalize(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping
            .split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    /// Host names written in the request, such as “subtis.io” or “www.youtube.com”.
    static func hosts(in prompt: String) -> Set<String> {
        let text = normalize(prompt)
        var found = Set<String>()
        let pattern = #"(?<![a-z0-9.-])([a-z0-9-]+(\.[a-z0-9-]+)+)"#
        var range = text.startIndex..<text.endIndex
        while let match = text.range(of: pattern, options: .regularExpression, range: range) {
            found.insert(strippingWWW(String(text[match]).trimmingCharacters(in: CharacterSet(charactersIn: "."))))
            range = match.upperBound..<text.endIndex
        }
        return found
    }

    private static func strippingWWW(_ host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func firstMatch(_ pattern: String, in texts: [String]) -> String? {
        for text in texts where !text.isEmpty {
            if let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                return String(text[range]).lowercased()
            }
        }
        return nil
    }

    private static func display(_ text: String) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if collapsed.isEmpty { return "this control" }
        return collapsed.count > 40 ? String(collapsed.prefix(39)) + "…" : collapsed
    }
}
