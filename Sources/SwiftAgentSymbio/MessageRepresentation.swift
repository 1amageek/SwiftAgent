//
//  MessageRepresentation.swift
//  SwiftAgentSymbio
//

import Foundation

public enum MessageRepresentationKind: String, Sendable, Codable, Hashable {
    case naturalLanguage
    case typedPayload
    case binaryFrame
    case controlPacket
    case sensoryFrame
}

public struct MessageRepresentation: Sendable, Codable, Hashable {
    public let kind: MessageRepresentationKind
    public let schema: String?
    public let contentType: String
    public let language: String?

    public init(
        kind: MessageRepresentationKind,
        schema: String? = nil,
        contentType: String,
        language: String? = nil
    ) {
        self.kind = kind
        self.schema = schema
        self.contentType = contentType
        self.language = language
    }

    public static func naturalLanguage(
        language: String? = nil,
        contentType: String = "text/plain"
    ) -> MessageRepresentation {
        MessageRepresentation(
            kind: .naturalLanguage,
            contentType: contentType,
            language: language
        )
    }

    public static func typedPayload(
        schema: String,
        contentType: String = "application/json"
    ) -> MessageRepresentation {
        MessageRepresentation(
            kind: .typedPayload,
            schema: schema,
            contentType: contentType
        )
    }
}
