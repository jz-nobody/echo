enum ConfirmationResponse: Sendable {
    case allow
    case deny
    case select(optionId: String)
    case multiSelect(optionIds: [String])
    case freeText(String)
}
