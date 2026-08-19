/// The default type-indexed ``ContextKey`` used by ``Contextable`` values.
///
/// Values are installed as immutable TaskLocal snapshots. Nested scopes copy
/// the small type map on write and TaskLocal restores the parent snapshot when
/// the operation finishes. No shared mutable storage crosses task boundaries.
public enum ContextValueKey<ContextValue: Contextable>: ContextKey {
    public typealias Value = ContextValue

    public static var defaultValue: ContextValue {
        ContextValue.defaultValue
    }

    public static var current: ContextValue {
        ContextValueScope.current.value(for: ContextValue.self) ?? defaultValue
    }

    public static func withValue<Result: Sendable>(
        _ value: ContextValue,
        operation: nonisolated(nonsending) () async throws -> Result
    ) async rethrows -> Result {
        let scopedValues = ContextValueScope.current.setting(value)
        return try await ContextValueScope.$current.withValue(
            scopedValues,
            operation: operation
        )
    }
}

private struct ContextValues: Sendable {
    private var values: [ObjectIdentifier: any Sendable] = [:]

    func value<Value: Sendable>(for type: Value.Type) -> Value? {
        values[ObjectIdentifier(type)] as? Value
    }

    func setting<Value: Sendable>(_ value: Value) -> ContextValues {
        var copy = self
        copy.values[ObjectIdentifier(Value.self)] = value
        return copy
    }
}

private enum ContextValueScope {
    @TaskLocal static var current = ContextValues()
}
