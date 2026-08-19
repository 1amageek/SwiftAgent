import SwiftAgent

@Generable
public struct FetchInput: Sendable {
    @Guide(description: "Fully qualified URL whose origin is authorized by the configured policy")
    public let url: String
}
