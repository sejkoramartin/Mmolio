//
//  MedtrumFrameAssembler.swift
//  MedProbe
//
//  Passive reassembly of the fragmented stream on characteristic 669A9101.
//
//  Framing mirrors the AndroidAPS `ReadDataPacket`
//  (nightscout/AndroidAPS, pump/medtrum/.../comm/ReadDataPacket.kt):
//
//      byte 0        total length of the logical message
//      byte 3        fragment sequence number, 1, 2, 3, …
//      last byte     CRC-8 over everything preceding it
//
//      first fragment      keep the whole frame minus its checksum
//      later fragments     strip the 4-byte header and the checksum, append the rest
//
//  MedProbe is a bystander here: in AndroidAPS this stream carries replies to commands
//  that app sends, whereas we are watching replies to commands EasyPatch sends. We
//  reassemble what is already flowing and never request anything. This file constructs
//  no messages and has no path that could reach the pump.
//
//  Reassembly only. The contents of a completed message are not interpreted anywhere.
//

import Foundation

/// A fully reassembled logical message from the 669A9101 fragment stream.
struct AssembledFrame: Equatable {

    /// Length the first fragment declared.
    let declaredLength: Int

    /// Concatenated payload, checksums and continuation headers removed.
    let payload: [UInt8]

    /// How many fragments were combined.
    let fragmentCount: Int

    /// True when every fragment's checksum matched and the sequence had no gaps.
    let isIntact: Bool

    var hex: String {
        payload.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    /// Byte 2 of the first fragment. Constant across a message's fragments and different
    /// between messages; AndroidAPS does not name it, so neither do we.
    var byteAtOffset2: UInt8? {
        payload.count > 2 ? payload[2] : nil
    }
}

/// Reassembles fragments as they arrive. One instance per characteristic.
///
/// Not thread-safe by design: it is driven from the BLE delegate on the main queue.
final class MedtrumFrameAssembler {

    private var payload: [UInt8] = []
    private var declaredLength = 0
    private var expectedSequence: UInt8 = 0
    private var fragmentCount = 0
    private var sawError = false
    private var inProgress = false

    /// How the assembler responded to a fragment.
    enum Outcome: Equatable {

        /// Fragment accepted, more expected.
        case accumulating(fragmentCount: Int, have: Int, need: Int)

        /// Message complete.
        case completed(AssembledFrame)

        /// Fragment rejected; the assembler reset. Reported so bad framing is visible
        /// rather than silently producing a wrong message.
        case discarded(reason: String)
    }

    /// Offers one received fragment to the assembler.
    @discardableResult
    func accept(_ data: Data) -> Outcome {
        let bytes = [UInt8](data)

        guard bytes.count >= 5 else {
            reset()
            return .discarded(reason: "fragment shorter than a header plus checksum (\(bytes.count) bytes)")
        }

        let checksumValid = MedtrumCrc8.isFrameIntact(data)
        let sequence = bytes[3]

        // A fragment numbered 1 always starts a new message, even if one was in progress:
        // as a passive listener we can join mid-message or miss a fragment entirely.
        if sequence == 1 || !inProgress {
            guard sequence == 1 else {
                return .discarded(reason: "joined mid-message at fragment \(sequence), waiting for a fresh one")
            }
            payload = Array(bytes.dropLast())
            declaredLength = Int(bytes[0])
            expectedSequence = 1
            fragmentCount = 1
            sawError = !checksumValid
            inProgress = true
        } else {
            let nextSequence = expectedSequence &+ 1
            guard sequence == nextSequence else {
                let missed = "expected fragment \(nextSequence), got \(sequence)"
                reset()
                return .discarded(reason: missed)
            }
            // Continuation fragments repeat the 4-byte header; only the middle is payload.
            payload.append(contentsOf: bytes.dropFirst(4).dropLast())
            expectedSequence = sequence
            fragmentCount += 1
            if !checksumValid { sawError = true }
        }

        guard payload.count >= declaredLength else {
            return .accumulating(fragmentCount: fragmentCount, have: payload.count, need: declaredLength)
        }

        let frame = AssembledFrame(
            declaredLength: declaredLength,
            payload: payload,
            fragmentCount: fragmentCount,
            isIntact: !sawError
        )
        reset()
        return .completed(frame)
    }

    func reset() {
        payload.removeAll()
        declaredLength = 0
        expectedSequence = 0
        fragmentCount = 0
        sawError = false
        inProgress = false
    }
}
