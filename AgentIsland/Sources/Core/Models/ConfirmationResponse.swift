enum ConfirmationResponse: Sendable {
    case allow
    case allowAlways(toolName: String)
    case autoApprove
    case deny
    case select(optionId: String)
    case multiSelect(optionIds: [String])
    case freeText(String)
}
