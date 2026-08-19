import Testing
@testable import SwiftAgentSymbio

@Suite("Participant record provenance")
struct ParticipantRecordTests {
    @Test("Descriptor replacement removes only stale declared affordances")
    func descriptorReplacementPreservesObservedAffordances() {
        let ownerID: ParticipantID = "participant.local"
        let representation = MessageRepresentation.typedPayload(
            schema: "test.payload"
        )
        let firstContract = CapabilityContract(
            id: "declared.first",
            input: representation
        )
        let secondContract = CapabilityContract(
            id: "declared.second",
            input: representation
        )
        let observedContract = CapabilityContract(
            id: "observed.external",
            input: representation
        )
        var record = ParticipantRecord(
            descriptor: ParticipantDescriptor(id: ownerID),
            declaredAffordances: [Affordance(
                id: firstContract.id,
                ownerID: ownerID,
                contract: firstContract
            )]
        )
        record.recordObservedAffordance(Affordance(
            id: observedContract.id,
            ownerID: ownerID,
            contract: observedContract,
            state: .degraded
        ))

        record.replaceDeclaredAffordances([Affordance(
            id: secondContract.id,
            ownerID: ownerID,
            contract: secondContract
        )])

        #expect(record.affordances.map(\.id) == [
            "declared.second",
            "observed.external",
        ])
        #expect(record.affordances.last?.state == .degraded)
    }
}
