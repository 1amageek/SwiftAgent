import Testing
import Foundation
@testable import SwiftAgent

// MARK: - Test Helpers for Map/Reduce

/// A step that doubles an integer
struct MapDoubleStep: Step, Sendable {
    func run(_ input: Int) async throws -> Int {
        input * 2
    }
}

/// A step that adds a fixed value to an integer
struct MapAddStep: Step, Sendable {
    let value: Int

    func run(_ input: Int) async throws -> Int {
        input + value
    }
}

/// A step that converts an integer to string with a prefix
struct MapToStringStep: Step, Sendable {
    let prefix: String

    func run(_ input: Int) async throws -> String {
        "\(prefix)\(input)"
    }
}

/// A step that formats with index
struct MapIndexedFormatStep: Step, Sendable {
    let index: Int

    func run(_ input: String) async throws -> String {
        "\(index):\(input)"
    }
}

/// A step that throws an error
struct MapTestErrorStep: Step, Sendable {
    struct TestError: Error {}

    func run(_ input: Int) async throws -> Int {
        throw TestError()
    }
}

/// A step that passes through the input unchanged
struct MapPassthroughIntStep: Step, Sendable {
    func run(_ input: Int) async throws -> Int {
        input
    }
}

/// A step that adds an integer to an accumulator
struct AccumulatorStep: Step, Sendable {
    let valueToAdd: Int

    func run(_ input: Int) async throws -> Int {
        input + valueToAdd
    }
}

/// A step that appends to a string with separator
struct StringAppendStep: Step, Sendable {
    let element: String

    func run(_ input: String) async throws -> String {
        input.isEmpty ? element : "\(input)-\(element)"
    }
}

/// A step that appends with index
struct IndexedAppendStep: Step, Sendable {
    let element: String
    let index: Int

    func run(_ input: String) async throws -> String {
        "\(input)\(index):\(element) "
    }
}

/// A step that finds the maximum
struct MaxStep: Step, Sendable {
    let candidate: Int

    func run(_ input: Int) async throws -> Int {
        max(input, candidate)
    }
}

/// Stats for testing complex accumulator
struct Stats: Sendable, Equatable {
    var count: Int = 0
    var sum: Int = 0

    var average: Double {
        count > 0 ? Double(sum) / Double(count) : 0
    }
}

/// A step that updates stats
struct StatsUpdateStep: Step, Sendable {
    let element: Int

    func run(_ input: Stats) async throws -> Stats {
        Stats(count: input.count + 1, sum: input.sum + element)
    }
}

/// A step that wraps value in brackets
struct MapBracketStep: Step, Sendable {
    func run(_ input: Int) async throws -> String {
        "[\(input)]"
    }
}

// MARK: - Map Tests

@Suite("Map Tests")
struct MapTests {

    @Test("Map transforms each element")
    func mapTransformsEachElement() async throws {
        let map = Map<Int, Int> { element, index in
            AnyStep(MapDoubleStep())
        }

        let result = try await map.run([1, 2, 3, 4, 5])
        #expect(result == [2, 4, 6, 8, 10])
    }

    @Test("Map with empty array returns empty")
    func mapEmptyArray() async throws {
        let map = Map<Int, Int> { element, index in
            AnyStep(MapDoubleStep())
        }

        let result = try await map.run([])
        #expect(result.isEmpty)
    }

    @Test("Map provides correct index")
    func mapProvidesCorrectIndex() async throws {
        let map = Map<String, String> { element, index in
            AnyStep(MapIndexedFormatStep(index: index))
        }

        let result = try await map.run(["a", "b", "c"])
        #expect(result == ["0:a", "1:b", "2:c"])
    }

    @Test("Map type conversion")
    func mapTypeConversion() async throws {
        let map = Map<Int, String> { element, index in
            AnyStep(MapToStringStep(prefix: "value:"))
        }

        let result = try await map.run([1, 2, 3])
        #expect(result == ["value:1", "value:2", "value:3"])
    }

    @Test("Map propagates errors")
    func mapPropagatesErrors() async throws {
        let map = Map<Int, Int> { element, index in
            AnyStep(MapTestErrorStep())
        }

        await #expect(throws: MapTestErrorStep.TestError.self) {
            try await map.run([1, 2, 3])
        }
    }

    @Test("Map preserves order")
    func mapPreservesOrder() async throws {
        let map = Map<Int, Int> { element, index in
            AnyStep(MapPassthroughIntStep())
        }

        let input = [5, 3, 1, 4, 2]
        let result = try await map.run(input)
        #expect(result == input)
    }

    @Test("Map with single element")
    func mapSingleElement() async throws {
        let map = Map<Int, Int> { element, index in
            AnyStep(MapAddStep(value: 10))
        }

        let result = try await map.run([5])
        #expect(result == [15])
    }
}

// MARK: - Reduce Tests

@Suite("Reduce Tests")
struct ReduceTests {

    @Test("Reduce sums array")
    func reduceSumsArray() async throws {
        let reduce = Reduce<[Int], Int>(initial: 0) { accumulator, element, index in
            AccumulatorStep(valueToAdd: element)
        }

        let result = try await reduce.run([1, 2, 3, 4, 5])
        #expect(result == 15)
    }

    @Test("Reduce with empty array returns initial value")
    func reduceEmptyArray() async throws {
        let reduce = Reduce<[Int], Int>(initial: 100) { accumulator, element, index in
            AccumulatorStep(valueToAdd: element)
        }

        let result = try await reduce.run([])
        #expect(result == 100)
    }

    @Test("Reduce concatenates strings")
    func reduceConcatenatesStrings() async throws {
        let reduce = Reduce<[String], String>(initial: "") { accumulator, element, index in
            StringAppendStep(element: element)
        }

        let result = try await reduce.run(["a", "b", "c"])
        #expect(result == "a-b-c")
    }

    @Test("Reduce with index")
    func reduceWithIndex() async throws {
        let reduce = Reduce<[String], String>(initial: "") { accumulator, element, index in
            IndexedAppendStep(element: element, index: index)
        }

        let result = try await reduce.run(["a", "b", "c"])
        #expect(result == "0:a 1:b 2:c ")
    }

    @Test("Reduce finds maximum")
    func reduceFindsMaximum() async throws {
        let reduce = Reduce<[Int], Int>(initial: Int.min) { accumulator, element, index in
            MaxStep(candidate: element)
        }

        let result = try await reduce.run([3, 1, 4, 1, 5, 9, 2, 6])
        #expect(result == 9)
    }

    @Test("Reduce propagates errors")
    func reducePropagatesErrors() async throws {
        struct ReduceTestError: Error {}
        struct ReduceErrorStep: Step, Sendable {
            func run(_ input: Int) async throws -> Int {
                throw ReduceTestError()
            }
        }

        let reduce = Reduce<[Int], Int>(initial: 0) { accumulator, element, index in
            ReduceErrorStep()
        }

        await #expect(throws: ReduceTestError.self) {
            try await reduce.run([1, 2, 3])
        }
    }

    @Test("Reduce with complex accumulator")
    func reduceWithComplexAccumulator() async throws {
        let reduce = Reduce<[Int], Stats>(initial: Stats()) { stats, element, index in
            StatsUpdateStep(element: element)
        }

        let result = try await reduce.run([10, 20, 30])
        #expect(result.count == 3)
        #expect(result.sum == 60)
        #expect(result.average == 20.0)
    }
}

// MARK: - Join Tests

@Suite("Join Tests")
struct JoinTests {

    @Test("Join with default separator")
    func joinDefaultSeparator() async throws {
        let join = Join()
        let result = try await join.run(["a", "b", "c"])
        #expect(result == "abc")
    }

    @Test("Join with custom separator")
    func joinCustomSeparator() async throws {
        let join = Join(separator: ", ")
        let result = try await join.run(["apple", "banana", "cherry"])
        #expect(result == "apple, banana, cherry")
    }

    @Test("Join empty array")
    func joinEmptyArray() async throws {
        let join = Join(separator: "-")
        let result = try await join.run([])
        #expect(result == "")
    }

    @Test("Join single element")
    func joinSingleElement() async throws {
        let join = Join(separator: "-")
        let result = try await join.run(["only"])
        #expect(result == "only")
    }

    @Test("Join with newline separator")
    func joinNewlineSeparator() async throws {
        let join = Join(separator: "\n")
        let result = try await join.run(["line1", "line2", "line3"])
        #expect(result == "line1\nline2\nline3")
    }

    @Test("Join with empty strings in array")
    func joinEmptyStrings() async throws {
        let join = Join(separator: "-")
        let result = try await join.run(["a", "", "b", "", "c"])
        #expect(result == "a--b--c")
    }
}

// MARK: - Combined Map/Reduce Tests

@Suite("Map Reduce Combined Tests")
struct MapReduceCombinedTests {

    @Test("Map then reduce")
    func mapThenReduce() async throws {
        // First double each element, then sum
        let map = Map<Int, Int> { element, index in
            AnyStep(MapDoubleStep())
        }

        let reduce = Reduce<[Int], Int>(initial: 0) { acc, element, index in
            AccumulatorStep(valueToAdd: element)
        }

        let mapped = try await map.run([1, 2, 3, 4, 5])
        let result = try await reduce.run(mapped)

        // [1,2,3,4,5] -> [2,4,6,8,10] -> sum = 30
        #expect(result == 30)
    }

    @Test("Map then join")
    func mapThenJoin() async throws {
        let map = Map<Int, String> { element, index in
            AnyStep(MapBracketStep())
        }

        let join = Join(separator: " ")

        let mapped = try await map.run([1, 2, 3])
        let result = try await join.run(mapped)

        #expect(result == "[1] [2] [3]")
    }
}
