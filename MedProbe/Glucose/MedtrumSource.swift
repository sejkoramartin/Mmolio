//
//  MedtrumSource.swift
//  MedProbe
//
//  Adapts the existing Medtrum BLE path to the common CGMSource interface.
//
//  Deliberately an adapter and nothing more: MedtrumPacketDecoder, MedtrumReading and
//  MedtrumBluetoothManager are untouched. Their tests keep passing unchanged, and the
//  verified decoding path — the one checked against EasyPatch — is not disturbed by the
//  introduction of a second source.
//

import Foundation
import Combine

/// Translates `MedtrumReading` into the normalised `GlucoseReading`.
enum MedtrumReadingAdapter {

    /// Medtrum packets carry no trend field. Rather than invent one, the trend is derived
    /// from the history slots the packet already contains — the same shift register the
    /// decoder exposes — and only when there is enough of it.
    ///
    /// Thresholds are in mg/dL per 2-minute cycle, chosen to match the arrows the Libre
    /// vocabulary uses: roughly 1, 2 and 3 mg/dL per minute.
    static func trend(from reading: MedtrumReading) -> GlucoseTrend {
        guard let previousRaw = reading.historyRawGlucose.first,
              reading.calibrationFactor > 0 else { return .unknown }

        let previousMgdl = Double(previousRaw) * 1000.0 / Double(reading.calibrationFactor)
        let deltaPerCycle = reading.mgdl - previousMgdl

        switch deltaPerCycle {
        case ..<(-6): return .fallingQuickly
        case ..<(-4): return .falling
        case ..<(-2): return .fallingSlightly
        case ..<2: return .steady
        case ..<4: return .risingSlightly
        case ..<6: return .rising
        default: return .risingQuickly
        }
    }

    /// Converts a decoded Medtrum packet into a normalised reading.
    ///
    /// The reading counter is the sequence: it advances by exactly one per 2-minute cycle
    /// and is already the basis of the existing duplicate and backfill handling.
    static func normalise(_ reading: MedtrumReading) -> GlucoseReading {
        GlucoseReading(
            mgdl: reading.mgdl,
            measuredAt: reading.receivedAt,
            trend: trend(from: reading),
            source: .medtrum,
            sequence: reading.counter
        )
    }

    /// Converts a reading recovered from a packet's history slots.
    ///
    /// Backfilled values carry the timestamp of the cycle they belong to, not the moment
    /// the carrying packet arrived, and no trend — a single historical value says nothing
    /// about direction on its own.
    static func normalise(_ backfilled: BackfilledReading) -> GlucoseReading {
        GlucoseReading(
            mgdl: backfilled.mgdl,
            measuredAt: backfilled.timestamp,
            trend: .unknown,
            source: .medtrum,
            sequence: backfilled.counter
        )
    }
}

/// Presents the Medtrum BLE manager as a `CGMSource`.
final class MedtrumSource: CGMSource {

    let kind: GlucoseSourceKind = .medtrum

    private(set) var latestReading: GlucoseReading?
    private(set) var state: GlucoseSourceState = .idle {
        didSet {
            guard state != oldValue else { return }
            stateSubject.send(state)
        }
    }

    var readingPublisher: AnyPublisher<GlucoseReading, Never> {
        readingSubject.eraseToAnyPublisher()
    }

    var statePublisher: AnyPublisher<GlucoseSourceState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    private let readingSubject = PassthroughSubject<GlucoseReading, Never>()
    private let stateSubject = PassthroughSubject<GlucoseSourceState, Never>()

    private let manager: MedtrumBluetoothManager
    private var acceptance = ReadingAcceptancePolicy()
    private var cancellables = Set<AnyCancellable>()
    private var isStarted = false

    init(manager: MedtrumBluetoothManager) {
        self.manager = manager
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        observeManager()
        manager.start()
        state = .connecting
    }

    func stop() {
        // The BLE manager is intentionally not torn down: it is owned by the app delegate
        // and its connection is shared with the diagnostic screen. Stopping this source
        // means we stop publishing, not that the radio work ends.
        cancellables.removeAll()
        isStarted = false
        state = .idle
    }

    private func observeManager() {
        manager.$lastReading
            .compactMap { $0 }
            .sink { [weak self] reading in
                self?.handle(MedtrumReadingAdapter.normalise(reading))
            }
            .store(in: &cancellables)

        manager.$lastBackfilled
            .sink { [weak self] backfilled in
                for recovered in backfilled {
                    self?.handle(MedtrumReadingAdapter.normalise(recovered))
                }
            }
            .store(in: &cancellables)

        manager.$connectionState
            .sink { [weak self] connectionState in
                self?.state = Self.map(connectionState)
            }
            .store(in: &cancellables)
    }

    private func handle(_ reading: GlucoseReading) {
        guard case .success(let accepted) = acceptance.accept(reading) else { return }
        latestReading = accepted
        readingSubject.send(accepted)
    }

    private static func map(_ connectionState: PumpConnectionState) -> GlucoseSourceState {
        switch connectionState {
        case .idle: return .idle
        case .scanning, .connecting: return .connecting
        case .connected: return .connecting
        case .subscribed: return .connected
        case .disconnected: return .failed(.transport("Disconnected from pump"))
        }
    }
}
