//
//  Memory.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/13.
//



import Foundation

/// A property wrapper that stores a value in memory.
///
/// `Memory` allows encapsulation of a value while providing
/// a `Relay` projection for reactive value management.
@frozen @propertyWrapper
public struct Memory<Value: Sendable>: Sendable {
    @usableFromInline
    internal final class Storage: @unchecked Sendable {
        @usableFromInline
        var value: Value
        
        @usableFromInline
        init(_ value: Value) {
            self.value = value
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
    @inlinable
    public var projectedValue: Relay<Value> {
        Relay(
            get: { self._storage.value },
            set: { self._storage.value = $0 }
        )
    }
}

/// A property wrapper and dynamic member lookup structure for value relays.
///
/// `Relay` provides a mechanism to wrap a value and access it dynamically through
/// closures, allowing for flexible and reactive value management.
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