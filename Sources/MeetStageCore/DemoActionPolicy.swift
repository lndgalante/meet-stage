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
    /// That dialog's own text, such as its title and message. It only decides
    /// whether trusting the app can answer a question about the dialog, and
    /// never allows anything by itself.
    public let dialogText: [String]
    /// Description, help, identifier, placeholder and container label.
    public let details: [String]

    public init(
        kind: Kind, label: String, labelIsData: Bool = false, isSecure: Bool = false, isSearchField: Bool = false,
        inDialog: Bool = false, dialogText: [String] = [], details: [String] = []
    ) {
        self.kind = kind
        self.label = label
        self.labelIsData = labelIsData && (kind == .row || kind == .cell)
        self.isSecure = isSecure
        self.isSearchField = isSearchField
        self.inDialog = inDialog
        self.dialogText = dialogText
        self.details = details
    }

    var texts: [String] { (labelIsData ? [] : [label]) + details.map(DemoActionPolicy.words) }
}

public enum DemoPolicyAction: Equatable, Sendable {
    case click(DemoPolicyElement)
    case type(field: DemoPolicyElement, text: String, submit: Bool)
    case navigate(URL)
    case pressKey
}

/// A question the presenter answers before a demo action runs.
public struct DemoApproval: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A link that names a destructive action, such as “Delete account” or “Sign out”.
        case riskyLink
        /// A menu item that sounds destructive.
        case riskyMenuItem
        /// A control in a dialog whose own text reads as harmless.
        case dialogButton
        /// A control in a dialog whose text sounds destructive or sensitive, or couldn't be read.
        case riskyDialogButton
        /// A control with no label or details to judge it by.
        case unlabelledControl
        /// Return after typing into a field that isn't for searching.
        case returnOutsideSearch
        /// Typed text the request doesn't contain.
        case unrequestedText
        /// A page on a host that is neither the start host nor named in the request.
        case unknownHost
        /// A page on a known host with a query the request doesn't contain.
        case unrequestedQuery

        /// Whether Always Allow for the app answers this question for the
        /// presenter. Never for what could send data to another site, submit a
        /// form, or act at once like “Sign out”, a destructive menu item or dialog.
        public var isCoveredByTrust: Bool {
            switch self {
            case .dialogButton, .unlabelledControl, .unrequestedText, .unrequestedQuery: true
            case .riskyLink, .riskyMenuItem, .riskyDialogButton, .returnOutsideSearch, .unknownHost: false
            }
        }
    }

    public let kind: Kind
    /// The question the presenter sees, which a step records when it's approved.
    public let message: String

    public init(_ kind: Kind, _ message: String) {
        self.kind = kind
        self.message = message
    }
}

public enum DemoPolicyDecision: Equatable, Sendable {
    case allow
    case needsApproval(DemoApproval)
    case deny(String)
}

/// Fail-closed rules for actions a demo performs in another app. The scout
/// checks them before every action and replay checks them again on the live
/// element, so an edited or tampered saved demo can't bypass them. Prompts to
/// the model repeat these rules, but the model is never the boundary.
public enum DemoActionPolicy {
    /// Stems match at the start of a word, so “Presets” never reads as “reset”,
    /// and “un” or “re” in front still counts (“Unstake”, “Resubmit”). The short
    /// ones match only as whole words (“pay” but not “payroll”). German stems
    /// match inside words too, since German joins them to prefixes (“Absenden”).
    static let destructivePattern =
        #"\b(un|re)?(delete|remove|erase|wipe|reset|discard|trash|sign ?out|log ?out|uninstall|purchase|checkout|place order|transfer|withdraw|swap|stake|approve|confirm|submit|publish|unsubscribe|cancel subscription|(pay|buy|send|sign|post|share|invite)\b)"#
        + #"|\b(eliminar|borrar|enviar|pagar|comprar|transferir|retirar|confirmar|cerrar sesi[oó]n|excluir|publicar)"#
        + #"|\b(supprimer|envoyer|payer|acheter|d[ée]connexion|virement)|l[öo]schen|senden|bezahlen|kaufen|abmelden|überweisen"#
        + #"|\b(elimina|cancella|invia|acquista|(paga|esci)\b)"#

    /// Endings that turn a stem into a list or a state rather than an action:
    /// “Transfers”, “Deleted”, “Submitted”, “Withdrawals”, “Confirmations”.
    static let inflectionPattern = #"^(e?s|e?d|[a-z]ed|als?|ations?)$"#

    static let sensitiveFieldPattern =
        #"pass(word|code|phrase)?|contraseña|mot de passe|kennwort|\bpin\b|\botp\b|2fa|one[- ]time|seed|recovery|secret|cvv|cvc|card number|iban|\bssn\b|private key|mnemonic"#

    static let searchPattern =
        #"search|find|filter|look ?up|buscar|busca|rechercher|recherche|suche|suchen|cerca|pesquis|zoek|検索|搜索"#

    /// Controls that only close or decline a dialog.
    static let dismissPattern =
        #"^(cancel|close|dismiss|not now|no thanks|got it|skip|maybe later|back|cancelar|cerrar|ahora no|annuler|fermer|abbrechen|schließen|annulla|chiudi|×|x)$"#

    /// How a dialog confirms something without naming it: “Are you sure?”, “This can't be undone.”
    static let warningPattern =
        #"are you sure|can(no|['’])t be undone|irreversible|permanent|est[aá]s? seguro|tem certeza|[êe]tes-vous s[ûu]r|sind sie sicher|sei sicuro"#

    /// `approved` answers any question; `appTrusted`, the presenter's Always
    /// Allow for the app, answers only the questions trust covers. Denials stay
    /// denials either way.
    public static func evaluate(
        _ action: DemoPolicyAction, prompt: String, startHost: String?, approved: Bool, appTrusted: Bool = false
    ) -> DemoPolicyDecision {
        let decision = rawDecision(action, prompt: prompt, startHost: startHost)
        if case .needsApproval(let approval) = decision, approved || (appTrusted && approval.kind.isCoveredByTrust) {
            return .allow
        }
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
            let riskyDialog = element.inDialog && !isHarmless(dialogText: element.dialogText)
            if let word = firstMatch(destructivePattern, in: element.texts) {
                switch element.kind {
                case .tab:
                    // Opening a view commits nothing; a destructive control inside it is still denied.
                    break
                case .link:
                    if let verb = firstVerb(in: element.texts) {
                        return .needsApproval(
                            DemoApproval(
                                riskyDialog ? .riskyDialogButton : .riskyLink,
                                "Open “\(display(element.label))”? It mentions “\(verb)”."))
                    }
                case .menuItem:
                    return .needsApproval(
                        DemoApproval(.riskyMenuItem, "Open “\(display(element.label))”? It mentions “\(word)”."))
                default:
                    return .deny(
                        element.label.isEmpty
                            ? "Pointing at this control instead of clicking it; it mentions “\(word)”."
                            : "Pointing at “\(display(element.label))” instead of clicking it.")
                }
            }
            if element.inDialog,
                element.label.range(of: dismissPattern, options: [.regularExpression, .caseInsensitive]) == nil
            {
                // A dialog's other buttons usually confirm whatever opened it.
                return .needsApproval(
                    DemoApproval(
                        riskyDialog ? .riskyDialogButton : .dialogButton,
                        "Click “\(display(element.label))” in this dialog?"))
            }
            if element.label.isEmpty, element.details.allSatisfy(\.isEmpty) {
                return .needsApproval(DemoApproval(.unlabelledControl, "Click an unlabelled control?"))
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
                return .needsApproval(
                    DemoApproval(
                        .returnOutsideSearch,
                        "Type “\(display(text))” and press Return in “\(display(field.label))”?"))
            }
            let typed = normalize(text)
            if typed.isEmpty || !normalize(prompt).contains(typed) {
                return .needsApproval(
                    DemoApproval(.unrequestedText, "Type “\(display(text))” into “\(display(field.label))”?"))
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
            if !knownHost { return .needsApproval(DemoApproval(.unknownHost, "Open \(display(host))?")) }
            let query = url.query.map(normalize) ?? ""
            if !query.isEmpty, !normalize(prompt).contains(query) {
                return .needsApproval(DemoApproval(.unrequestedQuery, "Open \(display(host))?"))
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

    /// Splits identifiers such as “btnDelete” or “action_delete” into words, so
    /// stems that must start a word still find them.
    static func words(_ text: String) -> String {
        text.replacingOccurrences(of: #"(?<=\p{Ll})(?=\p{Lu})|_"#, with: " ", options: .regularExpression)
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

    /// A dialog reads as harmless only when it has text and none of it sounds
    /// destructive, sensitive, or like a warning.
    private static func isHarmless(dialogText: [String]) -> Bool {
        dialogText.contains { !$0.isEmpty }
            && [destructivePattern, sensitiveFieldPattern, warningPattern].allSatisfy {
                firstMatch($0, in: dialogText) == nil
            }
    }

    private static func firstMatch(_ pattern: String, in texts: [String]) -> String? {
        for text in texts where !text.isEmpty {
            if let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                return String(text[range]).lowercased()
            }
        }
        return nil
    }

    /// The first destructive stem used as a verb, skipping plural and past forms.
    private static func firstVerb(in texts: [String]) -> String? {
        for text in texts where !text.isEmpty {
            var range = text.startIndex..<text.endIndex
            while let match = text.range(
                of: destructivePattern, options: [.regularExpression, .caseInsensitive], range: range)
            {
                let ending = text[match.upperBound...].prefix(while: \.isLetter)
                if ending.range(of: inflectionPattern, options: [.regularExpression, .caseInsensitive]) == nil {
                    return String(text[match]).lowercased()
                }
                // Past the whole word, so the next search starts where a word can.
                range = ending.endIndex..<text.endIndex
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
