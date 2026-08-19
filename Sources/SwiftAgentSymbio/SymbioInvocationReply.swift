import NetworkingCore

public enum SymbioInvocationFailureCode: String, Sendable, Codable, Hashable {
    case invalidRequest
    case notFound
    case unauthorized
    case deadlineExceeded
    case overloaded
    case unavailable
    case internalError
}

public struct SymbioInvocationFailure: Sendable, Codable, Hashable {
    public let code: SymbioInvocationFailureCode
    public let message: String

    public init(code: SymbioInvocationFailureCode, message: String) {
        self.code = code
        self.message = message
    }
}

public enum SymbioInvocationOutcome: Sendable, Hashable {
    case success(OwnedBytes?)
    case failure(SymbioInvocationFailure)
}

public struct SymbioInvocationReply: Sendable, Hashable {
    public let invocationID: String
    public let outcome: SymbioInvocationOutcome

    public init(invocationID: String, outcome: SymbioInvocationOutcome) {
        self.invocationID = invocationID
        self.outcome = outcome
    }

    public static func success(
        invocationID: String,
        result: OwnedBytes?
    ) -> SymbioInvocationReply {
        SymbioInvocationReply(invocationID: invocationID, outcome: .success(result))
    }

    public static func failure(
        invocationID: String,
        code: SymbioInvocationFailureCode,
        message: String
    ) -> SymbioInvocationReply {
        SymbioInvocationReply(
            invocationID: invocationID,
            outcome: .failure(SymbioInvocationFailure(code: code, message: message))
        )
    }
}
