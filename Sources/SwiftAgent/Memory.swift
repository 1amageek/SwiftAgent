//
//  Memory.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/13.
//

import Foundation
import Synchronization

/// A property wrapper that stores a value with reference semantics for state sharing.
///
/// `Memory` provides mutable state that can be shared across multiple ``Step`` instances.
/// Use the `$` prefix to get a ``Relay`` for passing state to child steps.
///
/// ## Overview
///
/// Memory wraps a value in a thread-safe container using `Mutex`. When you copy a struct
/// containing `@Memory`, both copies share the same underlying storage.
///
/// ```swift
/// @Memory var counter: Int = 0
/// counter += 1  // Modifies the shared storage
/// ```
///
/// ## Sharing State with Relay
///
/// Use the `$` prefix to get a ``Relay`` for passing to other steps:
///
/// ```swift
/// struct Orchestrator: Step {
///     @Memory var visitedURLs: Set<URL> = []
///
///     func run(_ input: URL) async throws -> [Data] {
///         // Pass relay to child steps
///         try await CrawlStep(visited: $visitedURLs).run(input)
///     }
/// }
///
/// struct CrawlStep: Step {
///     let visited: Relay<Set<URL>>
///
///     func run(_ input: URL) async throws -> Data {
///         guard !visited.contains(input) else { throw AlreadyVisited() }
///         visited.insert(input)
///         // ... fetch data
///     }
/// }
/// ```
///
/// ## Thread Safety
///
/// Memory uses `Mutex` internally, making it safe to access from multiple tasks.
/// However, compound operations (read-modify-write) are not atomic. For atomic
/// updates, access the value directly rather than through Relay's convenience methods.
@frozen @propertyWrapper
public struct Memory<Value: Sendable>: Sendable {

    @usableFromInline
    internal final class Storage: Sendable {
        @usableFromInline
        let mutex: Mutex<Value>

        @usableFromInline
        var value: Value {
            get { mutex.withLock { $0 } }
            set { mutex.withLock { $0 = newValue } }
        }

        @usableFromInline
        init(_ value: Value) {
            self.mutex = Mutex(value)
        }
    }

    @usableFromInline
    internal let _storage: Storage

    /// Initializes a new `Memory` property wrapper with an initial value.
    ///
    /// - Parameter wrappedValue: The initial value to store.
    @inlinable
    public init(wrappedValue value: Value) {
        self._storage = Storage(value)
    }

    /// The stored value.
    @inlinable
    public var wrappedValue: Value {
        get { _storage.value }
        nonmutating set { _storage.value = newValue }
    }

    /// A `Relay` projection of the stored value, enabling dynamic access and updates.
    ///
    /// Use the `$` prefix to get a Relay that can be passed to other Steps:
    /// ```swift
    /// @Memory var counter: Int = 0
    /// ChildStep(counter: $counter)  // Pass Relay to child
    /// ```
    @inlinable
    public var projectedValue: Relay<Value> {
        Relay(
            get: { self._storage.value },
            set: { self._storage.value = $0 }
        )
    }
}

// MARK: - Relay

/// A property wrapper providing indirect access to a value through getter/setter closures.
///
/// `Relay` enables shared mutable state between steps without direct storage ownership.
/// It's typically obtained from ``Memory``'s projected value using `$`.
///
/// ## Overview
///
/// Relay wraps getter and setter closures, allowing multiple steps to read and write
/// to the same underlying storage:
///
/// ```swift
/// struct ChildStep: Step {
///     let counter: Relay<Int>
///
///     func run(_ input: String) async throws -> String {
///         counter.wrappedValue += 1
///         return "\(input) #\(counter.wrappedValue)"
///     }
/// }
/// ```
///
/// ## Creating Relays
///
/// - From Memory: `$myMemory` returns a Relay
/// - Constant: `Relay.constant(value)` creates a read-only relay
/// - Custom: `Relay(get: { ... }, set: { ... })`
///
/// ## Collection Extensions
///
/// Relay provides convenience methods for common collection operations:
///
/// ```swift
/// @Memory var items: Set<Int> = []
/// $items.insert(1)       // Insert into set
/// $items.contains(1)     // Check membership
/// $items.formUnion([2])  // Union with another set
///
/// @Memory var list: [String] = []
/// $list.append("item")   // Append to array
/// ```
///
/// ## Transformations
///
/// Transform relay values with `map` and `readOnly`:
///
/// ```swift
/// @Memory var celsius: Double = 0
/// let fahrenheit = $celsius.map(
///     { $0 * 9/5 + 32 },
///     reverse: { ($0 - 32) * 5/9 }
/// )
/// ```
@frozen @propertyWrapper
public struct Relay<Value: Sendable>: Sendable {

    @usableFromInline
    internal struct Binding: @unchecked Sendable {
        @usableFromInline
        var get: @Sendable () -> Value

        @usableFromInline
        var set: @Sendable (Value) -> Void

        @usableFromInline
        init(get: @escaping @Sendable () -> Value, set: @escaping @Sendable (Value) -> Void) {
            self.get = get
            self.set = set
        }
    }

    @usableFromInline
    internal var _value: Binding

    @usableFromInline
    internal init(value: Binding) {
        self._value = value
    }

    /// Initializes a new relay with getter and setter closures.
    ///
    /// - Parameters:
    ///   - get: A closure that retrieves the current value.
    ///   - set: A closure that updates the value.
    @inlinable
    public init(get: @escaping @Sendable () -> Value, set: @escaping @Sendable (Value) -> Void) {
        self._value = Binding(get: get, set: set)
    }

    /// Creates a constant, immutable relay.
    ///
    /// - Parameter value: The immutable value to be wrapped.
    /// - Returns: A `Relay` instance with a fixed value.
    @inlinable
    public static func constant(_ value: Value) -> Relay<Value> {
        return Relay(value: Binding(
            get: { value },
            set: { _ in }
        ))
    }

    /// The current value referenced by the relay.
    @inlinable
    public var wrappedValue: Value {
        get { _value.get() }
        nonmutating set { _value.set(newValue) }
    }

    /// A projection of the relay that can be passed to child steps or components.
    @inlinable
    public var projectedValue: Relay<Value> { self }

    /// Initializes a new relay from another relay's projected value.
    ///
    /// - Parameter projectedValue: An existing relay to copy.
    @inlinable
    public init(projectedValue: Relay<Value>) {
        self = projectedValue
    }
}

// MARK: - Optional Support

extension Relay {

    /// Initializes a relay by projecting an optional base value.
    ///
    /// - Parameter base: A relay that wraps a non-optional value.
    @inlinable
    public init<V: Sendable>(_ base: Relay<V>) where Value == V? {
        self._value = Binding(
            get: { Optional(base.wrappedValue) },
            set: { newValue in
                if let value = newValue {
                    base.wrappedValue = value
                }
            }
        )
    }

    /// Initializes a relay by projecting an optional base value to an unwrapped value.
    ///
    /// - Parameter base: A relay that wraps an optional value.
    /// - Returns: A `Relay` instance if the base contains a non-nil value, otherwise `nil`.
    @inlinable
    public init?(_ base: Relay<Value?>) {
        guard let value = base.wrappedValue else { return nil }
        self._value = Binding(
            get: { base.wrappedValue ?? value },
            set: { base.wrappedValue = $0 }
        )
    }
}

// MARK: - Relay Transformations

extension Relay {

    /// Creates a new Relay that transforms the value using the provided closures.
    ///
    /// - Parameters:
    ///   - transform: A closure that transforms the original value.
    ///   - reverse: A closure that transforms back to the original type.
    /// - Returns: A new Relay with the transformed type.
    @inlinable
    public func map<T: Sendable>(
        _ transform: @escaping @Sendable (Value) -> T,
        reverse: @escaping @Sendable (T) -> Value
    ) -> Relay<T> {
        Relay<T>(
            get: { transform(self.wrappedValue) },
            set: { self.wrappedValue = reverse($0) }
        )
    }

    /// Creates a read-only Relay by applying a transform.
    ///
    /// - Parameter transform: A closure that transforms the value.
    /// - Returns: A new Relay that ignores set operations.
    @inlinable
    public func readOnly<T: Sendable>(
        _ transform: @escaping @Sendable (Value) -> T
    ) -> Relay<T> {
        Relay<T>(
            get: { transform(self.wrappedValue) },
            set: { _ in }
        )
    }
}

// MARK: - Collection Extensions

extension Relay where Value: RangeReplaceableCollection, Value: Sendable, Value.Element: Sendable {

    /// Appends an element to the collection.
    @inlinable
    public func append(_ element: Value.Element) {
        var collection = wrappedValue
        collection.append(element)
        wrappedValue = collection
    }

    /// Appends a sequence of elements to the collection.
    @inlinable
    public func append<S: Sequence>(contentsOf newElements: S) where S.Element == Value.Element {
        var collection = wrappedValue
        collection.append(contentsOf: newElements)
        wrappedValue = collection
    }

    /// Removes all elements from the collection.
    @inlinable
    public func removeAll() {
        var collection = wrappedValue
        collection.removeAll()
        wrappedValue = collection
    }
}

extension Relay where Value: SetAlgebra, Value: Sendable, Value.Element: Sendable {

    /// Inserts an element into the set.
    @inlinable
    @discardableResult
    public func insert(_ element: Value.Element) -> (inserted: Bool, memberAfterInsert: Value.Element) {
        var set = wrappedValue
        let result = set.insert(element)
        wrappedValue = set
        return result
    }

    /// Removes an element from the set.
    @inlinable
    @discardableResult
    public func remove(_ element: Value.Element) -> Value.Element? {
        var set = wrappedValue
        let result = set.remove(element)
        wrappedValue = set
        return result
    }

    /// Checks if the set contains the element.
    @inlinable
    public func contains(_ element: Value.Element) -> Bool {
        wrappedValue.contains(element)
    }

    /// Forms the union with another set.
    @inlinable
    public func formUnion<S: Sequence>(_ other: S) where S.Element == Value.Element {
        var set = wrappedValue
        for element in other {
            set.insert(element)
        }
        wrappedValue = set
    }
}

extension Relay where Value == Int {

    /// Increments the value by 1.
    @inlinable
    public func increment() {
        wrappedValue += 1
    }

    /// Decrements the value by 1.
    @inlinable
    public func decrement() {
        wrappedValue -= 1
    }

    /// Adds the specified value.
    @inlinable
    public func add(_ value: Int) {
        wrappedValue += value
    }
}
