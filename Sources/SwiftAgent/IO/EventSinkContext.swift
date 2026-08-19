/// Context key for ``EventSink``, enabling `@Context var events: EventSink`.
public enum EventSinkContext: ContextKey {
    @TaskLocal private static var _current: EventSink?

    public static var defaultValue: EventSink { .null }

    public static var current: EventSink { _current ?? defaultValue }

    public static func withValue<T: Sendable>(
        _ value: EventSink,
        operation: nonisolated(nonsending) () async throws -> T
    ) async rethrows -> T {
        try await $_current.withValue(value, operation: operation)
    }
}

extension EventSink: Contextable {
    public static var defaultValue: EventSink { .null }

    public static var current: EventSink {
        EventSinkContext.current
    }

    public static func withValue<Result: Sendable>(
        _ value: EventSink,
        operation: nonisolated(nonsending) () async throws -> Result
    ) async rethrows -> Result {
        try await EventSinkContext.withValue(value, operation: operation)
    }
}
