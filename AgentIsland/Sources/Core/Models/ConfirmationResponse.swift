enum ConfirmationResponse: Sendable {
    case allow
    case deny
    case select(optionId: String)
}
