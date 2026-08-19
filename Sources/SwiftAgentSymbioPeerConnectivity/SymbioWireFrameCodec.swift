import Foundation
import NIOCore
import PeerConnectivity

/// Converts one bounded Symbio payload to and from a byte-stream frame.
///
/// Each protocol stream carries exactly one frame in each direction. The frame
/// starts with a four-byte, unsigned big-endian payload length followed by the
/// JSON payload. Transport read boundaries have no application-level meaning.
struct SymbioWireFrameCodec: Sendable {
    static let headerByteCount = MemoryLayout<UInt32>.size

    let maximumPayloadBytes: Int

    func validateConfiguration() throws {
        guard maximumPayloadBytes > 0 else {
            throw PeerConnectivitySymbioError.invalidConfiguration(
                "wire message limit must be greater than zero"
            )
        }
        guard maximumPayloadBytes <= Int.max - Self.headerByteCount,
              UInt64(maximumPayloadBytes) <= UInt64(UInt32.max) else {
            throw PeerConnectivitySymbioError.invalidConfiguration(
                "wire message limit must fit in the four-byte frame length"
            )
        }
    }

    func frame(_ payload: Data) throws -> ByteBuffer {
        try validateConfiguration()
        guard !payload.isEmpty else {
            throw PeerConnectivitySymbioError.invalidWireMessage(
                "Wire payload must not be empty"
            )
        }
        guard payload.count <= maximumPayloadBytes else {
            throw PeerConnectivitySymbioError.wireMessageTooLarge(
                actual: payload.count,
                maximum: maximumPayloadBytes
            )
        }
        guard let payloadLength = UInt32(exactly: payload.count) else {
            throw PeerConnectivitySymbioError.wireMessageTooLarge(
                actual: payload.count,
                maximum: maximumPayloadBytes
            )
        }

        var frame = ByteBufferAllocator().buffer(
            capacity: Self.headerByteCount + payload.count
        )
        frame.writeInteger(payloadLength, endianness: .big)
        frame.writeBytes(payload)
        return frame
    }

    func readFrame(
        from channel: any PeerConnectivityChannel
    ) async throws -> Data {
        try validateConfiguration()

        var header: [UInt8] = []
        header.reserveCapacity(Self.headerByteCount)
        var payload = Data()
        var expectedPayloadBytes: Int?

        while true {
            var chunk = try await channel.read()
            guard chunk.readableBytes > 0 else {
                throw PeerConnectivitySymbioError.invalidWireMessage(
                    "PeerConnectivity returned an empty stream chunk"
                )
            }

            if header.count < Self.headerByteCount {
                let headerBytes = Swift.min(
                    Self.headerByteCount - header.count,
                    chunk.readableBytes
                )
                header.append(
                    contentsOf: chunk.readableBytesView.prefix(headerBytes)
                )
                chunk.moveReaderIndex(forwardBy: headerBytes)

                if header.count == Self.headerByteCount {
                    var declaredLength: UInt32 = 0
                    for byte in header {
                        declaredLength = (declaredLength << 8) | UInt32(byte)
                    }
                    let declaredPayloadBytes = Int(declaredLength)
                    guard declaredPayloadBytes > 0 else {
                        throw PeerConnectivitySymbioError.invalidWireMessage(
                            "Wire frame declared an empty payload"
                        )
                    }
                    guard declaredPayloadBytes <= maximumPayloadBytes else {
                        throw PeerConnectivitySymbioError.wireMessageTooLarge(
                            actual: declaredPayloadBytes,
                            maximum: maximumPayloadBytes
                        )
                    }
                    expectedPayloadBytes = declaredPayloadBytes
                    // Allocate only after the untrusted declared length is bounded.
                    payload.reserveCapacity(declaredPayloadBytes)
                }
            }

            guard let expectedPayloadBytes else {
                continue
            }
            let remainingPayloadBytes = expectedPayloadBytes - payload.count
            guard chunk.readableBytes <= remainingPayloadBytes else {
                throw PeerConnectivitySymbioError.invalidWireMessage(
                    "Wire frame contained bytes after its declared payload"
                )
            }
            payload.append(contentsOf: chunk.readableBytesView)

            if payload.count == expectedPayloadBytes {
                return payload
            }
        }
    }
}
