//
//  TurnCancellationTokenTests.swift
//  SwiftAgent
//

import Testing
import Foundation
@testable import SwiftAgent

@Suite("TurnCancellationToken Tests")
struct TurnCancellationTokenTests {

    @Test("Initial state is not cancelled")
    func initialStateNotCancelled() {
        let token = TurnCancellationToken()
        #expect(token.isCancelled == false)
    }

    @Test("cancel() sets isCancelled to true")
    func cancelSetsCancelled() {
        let token = TurnCancellationToken()
        token.cancel()
        #expect(token.isCancelled == true)
    }

    @Test("checkCancellation() throws when cancelled")
    func checkCancellationThrowsWhenCancelled() {
        let token = TurnCancellationToken()
        token.cancel()
        #expect(throws: CancellationError.self) {
            try token.checkCancellation()
        }
    }

    @Test("checkCancellation() does not throw when not cancelled")
    func checkCancellationNoThrowWhenNotCancelled() throws {
        let token = TurnCancellationToken()
        try token.checkCancellation()
    }

    @Test("cancel() is idempotent")
    func cancelIsIdempotent() {
        let token = TurnCancellationToken()
        token.cancel()
        token.cancel()
        #expect(token.isCancelled == true)
    }

    @Test("Context propagation via withValue", .timeLimit(.minutes(1)))
    func contextPropagation() async throws {
        let token = TurnCancellationToken()

        let retrieved = await TurnCancellationContext.withValue(token) {
            TurnCancellationContext.current
        }

        #expect(retrieved === token)
    }

    @Test("Context default is nil")
    func contextDefaultIsNil() {
        let current = TurnCancellationContext.current
        #expect(current == nil)
    }
}
