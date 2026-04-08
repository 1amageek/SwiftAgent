//
//  ToolsBuilder.swift
//  SwiftAgent
//

/// A result builder for declaratively composing tool collections.
///
/// Use `@ToolsBuilder` to build `[any Tool]` with conditional logic:
///
/// ```swift
/// @ToolsBuilder
/// var tools: [any Tool] {
///     ReadTool()
///     WriteTool()
///     if enableSearch {
///         GrepTool()
///     }
/// }
/// ```
@resultBuilder
public struct ToolsBuilder {

    public static func buildExpression(_ tool: any Tool) -> [any Tool] {
        [tool]
    }

    public static func buildExpression(_ tools: [any Tool]) -> [any Tool] {
        tools
    }

    public static func buildBlock(_ components: [any Tool]...) -> [any Tool] {
        components.flatMap { $0 }
    }

    public static func buildOptional(_ component: [any Tool]?) -> [any Tool] {
        component ?? []
    }

    public static func buildEither(first component: [any Tool]) -> [any Tool] {
        component
    }

    public static func buildEither(second component: [any Tool]) -> [any Tool] {
        component
    }

    public static func buildArray(_ components: [[any Tool]]) -> [any Tool] {
        components.flatMap { $0 }
    }
}
