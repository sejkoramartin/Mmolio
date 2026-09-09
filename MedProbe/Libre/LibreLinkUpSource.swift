//
//  LibreLinkUpSource.swift
//  MedProbe
//
//  Presents LibreLinkUp as a CGMSource: polls, deduplicates, and reports its own state.
//
//  Read-only follower access. Nothing here touches the sensor — see LibreLinkUpAPI for
//  the full statement of what this does and does not do.
//

import Foundation
import Combine

final class LibreLinkUpSource: CGMSource {

    let kind: GlucoseSourceKind = .libreLinkUp

    /// How often to poll when nothing prompts us. The Libre sensor produces a value each
    /// minute, but LibreLinkUp lags behind the phone's own upload, so asking faster gains
    /// nothing and risks the service's rate limits.
    static let defaultPollInterval: TimeInterval = 60

    /// Never ask again sooner than this, whatever prompts a fetch. Protects the service
    /// from the heartbeat listener firing repeatedly.
    static let minimumFetchInterval: TimeInterval = 20

    private(set) var latestReading: GlucoseReading?
    private(set) var state: GlucoseSourceState = .disabled {
        didSet {
            guard state != oldValue else { return }
            stateSubject.send(state)
        }
    }

    var readingPublisher: AnyPublisher<GlucoseReading, Never> { readingSubject.eraseToAnyPublisher() }
    var statePublisher: AnyPublisher<GlucoseSourceState, Never> { stateSubject.eraseToAnyPublisher() }

    /// Last error, kept for display after the state has moved on.
    private(set) var lastError: GlucoseSourceError?
    private(set) var lastSuccessfulFetch: Date?

    private let readingSubject = PassthroughSubject<GlucoseReading, Never>()
    private let stateSubject = PassthroughSubject<GlucoseSourceState, Never>()

    private let api: LibreLinkUpFetching
    private let credentials: LibreCredentials
    private let log: DiagnosticLog
    private let pollInterval: TimeInterval

    private var acceptance = ReadingAcceptancePolicy()
    private var timer: Timer?
    private var isFetching = false
    private var lastFetchAttempt: Date?

    init(api: LibreLinkUpFetching,
         credentials: LibreCredentials,
         log: DiagnosticLog,
         pollInterval: TimeInterval = LibreLinkUpSource.defaultPollInterval) {
        self.api = api
        self.credentials = credentials
        self.log = log
        self.pollInterval = pollInterval
    }

    // MARK: - lifecycle

    func start() {
        guard credentials.hasLogin else {
            state = .failed(.notAuthenticated("no LibreLinkUp account configured"))
            return
        }

        state = .connecting
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.fetch(reason: "poll")
        }
        fetch(reason: "start")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        state = .disabled
    }

    /// Asks for a reading outside the normal schedule.
    ///
    /// Used by the experimental heartbeat listener: a BLE notification from the sensor is
    /// a hint that a new value exists, and this is the only thing that hint is allowed to
    /// do. Rate limiting applies exactly as it does to a scheduled poll.
    func requestImmediateFetch(reason: String) {
        fetch(reason: reason)
    }

    // MARK: - fetching

    private func fetch(reason: String) {
        guard credentials.hasLogin else {
            report(.notAuthenticated("no LibreLinkUp account configured"))
            return
        }
        guard !isFetching else { return }

        if let last = lastFetchAttempt {
            let sinceLast = Date().timeIntervalSince(last)
            guard sinceLast >= Self.minimumFetchInterval else {
                log.info("Libre fetch (\(reason)) skipped: \(Int(Self.minimumFetchInterval - sinceLast))s of rate limit left", .diagnostic)
                return
            }
        }

        isFetching = true
        lastFetchAttempt = Date()

        Task { [weak self] in
            guard let self else { return }
            await self.performFetch(reason: reason, allowReauthentication: true)
            await MainActor.run { self.isFetching = false }
        }
    }

    /// One fetch, with a single re-authentication attempt.
    ///
    /// A 401 is expected periodically: LibreLinkUp tokens expire. It is retried exactly
    /// once, because a genuinely rejected password must surface as an error rather than
    /// looping and getting the account locked.
    private func performFetch(reason: String, allowReauthentication: Bool) async {
        do {
            let session = try await currentSession()
            let measurement = try await api.fetchLatest(session: session, region: credentials.region)
            await MainActor.run { self.accept(measurement, reason: reason) }

        } catch let error as GlucoseSourceError {
            if case .notAuthenticated = error, allowReauthentication {
                await MainActor.run {
                    self.log.info("Libre session rejected, signing in again", .diagnostic)
                    self.credentials.clearSession()
                }
                await performFetch(reason: reason, allowReauthentication: false)
                return
            }
            await MainActor.run { self.report(error) }

        } catch {
            await MainActor.run { self.report(.transport(error.localizedDescription)) }
        }
    }

    /// Returns a usable session, signing in if there is not one already.
    private func currentSession() async throws -> LibreSession {
        if let token = credentials.token, let accountID = credentials.accountID {
            return LibreSession(token: token,
                                accountID: accountID,
                                patientID: credentials.patientID,
                                host: credentials.host ?? LibreLinkUpAPI.globalHost)
        }

        guard let email = credentials.email, let password = credentials.password else {
            throw GlucoseSourceError.notAuthenticated("no LibreLinkUp account configured")
        }

        let session = try await api.authenticate(email: email, password: password, region: credentials.region)

        await MainActor.run {
            self.credentials.token = session.token
            self.credentials.accountID = session.accountID
            // Remember where the account actually turned out to live, so later requests
            // and later launches go straight there.
            self.credentials.host = session.host
            if let patientID = session.patientID { self.credentials.patientID = patientID }
        }
        return session
    }

    // MARK: - results

    private func accept(_ measurement: LibreGlucoseMeasurement, reason: String) {
        lastSuccessfulFetch = Date()
        lastError = nil
        state = .connected

        let reading = Self.normalise(measurement)

        switch acceptance.accept(reading) {
        case .success(let accepted):
            latestReading = accepted
            readingSubject.send(accepted)
            log.info(String(format: "Libre reading %.1f mmol/L (%@)", accepted.mmoll, reason), .cgm)
        case .failure:
            // Expected: polling is faster than the sensor produces values.
            break
        }
    }

    private func report(_ error: GlucoseSourceError) {
        lastError = error
        state = .failed(error)
        log.warning("Libre: \(error.userFacingDescription)", .cgm)
    }

    /// Converts to the normalised type.
    ///
    /// LibreLinkUp has no sequence number, so the measurement time provides one: whole
    /// seconds since the epoch. It is monotonic for a given source, which is all the
    /// deduplication rule requires, and identical timestamps mean identical readings.
    static func normalise(_ measurement: LibreGlucoseMeasurement) -> GlucoseReading {
        GlucoseReading(
            mgdl: measurement.mgdl,
            measuredAt: measurement.timestamp,
            trend: LibreLinkUpAPI.trend(fromArrow: measurement.trendArrow),
            source: .libreLinkUp,
            sequence: Int(measurement.timestamp.timeIntervalSince1970)
        )
    }
}
