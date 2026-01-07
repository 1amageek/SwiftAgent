//
//  ContextableMacro.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/07.
//

import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftCompilerPlugin

/// Implementation of the `@Contextable` macro.
///
/// This macro generates:
/// - A peer `{TypeName}Context` enum conforming to `ContextKey`
/// - An extension with `typealias ContextKeyType`
public struct ContextableMacro: PeerMacro, ExtensionMacro {

    // MARK: - PeerMacro

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let typeName = extractTypeName(from: declaration) else {
            throw ContextableMacroError.unsupportedDeclaration
        }

        let accessModifier = extractAccessModifier(from: declaration)
        let accessPrefix = accessModifier.map { "\($0) " } ?? ""
        let contextKeyName = "\(typeName)Context"

        let contextKeyDecl: DeclSyntax = """
            \(raw: accessPrefix)enum \(raw: contextKeyName): ContextKey {
                @TaskLocal private static var _current: \(raw: typeName)?

                \(raw: accessPrefix)static var defaultValue: \(raw: typeName) { \(raw: typeName).defaultValue }

                \(raw: accessPrefix)static var current: \(raw: typeName) { _current ?? defaultValue }

                \(raw: accessPrefix)static func withValue<T: Sendable>(
                    _ value: \(raw: typeName),
                    operation: () async throws -> T
                ) async rethrows -> T {
                    try await $_current.withValue(value, operation: operation)
                }
            }
            """

        return [contextKeyDecl]
    }

    // MARK: - ExtensionMacro

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let typeName = extractTypeName(from: declaration) else {
            throw ContextableMacroError.unsupportedDeclaration
        }

        let contextKeyName = "\(typeName)Context"

        let extensionDecl: DeclSyntax = """
            extension \(raw: typeName) {
                typealias ContextKeyType = \(raw: contextKeyName)
            }
            """

        guard let ext = extensionDecl.as(ExtensionDeclSyntax.self) else {
            return []
        }

        return [ext]
    }

    /// Extracts the access modifier from a declaration.
    private static func extractAccessModifier(from declaration: some DeclSyntaxProtocol) -> String? {
        let modifiers: DeclModifierListSyntax?

        if let structDecl = declaration.as(StructDeclSyntax.self) {
            modifiers = structDecl.modifiers
        } else if let classDecl = declaration.as(ClassDeclSyntax.self) {
            modifiers = classDecl.modifiers
        } else if let enumDecl = declaration.as(EnumDeclSyntax.self) {
            modifiers = enumDecl.modifiers
        } else if let actorDecl = declaration.as(ActorDeclSyntax.self) {
            modifiers = actorDecl.modifiers
        } else {
            modifiers = nil
        }

        guard let modifiers else { return nil }

        for modifier in modifiers {
            let name = modifier.name.text
            if ["public", "internal", "fileprivate", "private", "package"].contains(name) {
                return name
            }
        }

        return nil
    }

    /// Extracts the type name from a declaration.
    private static func extractTypeName(from declaration: some DeclSyntaxProtocol) -> String? {
        if let structDecl = declaration.as(StructDeclSyntax.self) {
            return structDecl.name.text
        } else if let classDecl = declaration.as(ClassDeclSyntax.self) {
            return classDecl.name.text
        } else if let enumDecl = declaration.as(EnumDeclSyntax.self) {
            return enumDecl.name.text
        } else if let actorDecl = declaration.as(ActorDeclSyntax.self) {
            return actorDecl.name.text
        }
        return nil
    }
}

// MARK: - Errors

/// Errors that can occur during `@Contextable` macro expansion.
public enum ContextableMacroError: Error, CustomStringConvertible {
    case unsupportedDeclaration

    public var description: String {
        switch self {
        case .unsupportedDeclaration:
            return "@Contextable can only be applied to struct, class, enum, or actor declarations"
        }
    }
}

// MARK: - Plugin Entry Point

@main
struct SwiftAgentMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ContextableMacro.self,
    ]
}
