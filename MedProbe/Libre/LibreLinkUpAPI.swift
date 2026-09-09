//
//  LibreLinkUpAPI.swift
//  MedProbe
//
//  HTTP client for LibreLinkUp.
//
//  ── What this is, and what it is not ────────────────────────────────────────────────
//  LibreLinkUp is Abbott's *follower* service: the same thing a family member uses to
//  watch someone else's readings. MedProbe signs in as a follower and reads what the
//  official Libre app has already uploaded.
//
//  It does not touch the sensor. No NFC, no BLE to the sensor, no activation, no
//  streaming unlock. The official app stays the only thing that owns the sensor, keeps
//  its alarms, and keeps uploading to LibreView.
//
//  LibreLinkUp is not a documented public API. It changes without notice, so everything
//  specific to it is confined to this file behind LibreLinkUpFetching, and the rest of
//  the app depends on the protocol rather than on the endpoints.
//  ────────────────────────────────────────────────────────────────────────────────────
//

import Foundation
import CryptoKit

/// LibreLinkUp regional endpoints. Choosing the wrong one produces a confusing
/// authentication failure rather than an obvious error, so it is explicit and stored.
enum LibreRegion: String, CaseIterable, Identifiable {
    case europe = "eu"
    case unitedStates = "us"
    case germany = "de"
    case france = "fr"
    case japan = "jp"
    case asiaPacific = "ap"
    case australia = "au"
    case canada = "ca"

    var id: String { rawValue }

    var host: String {
        switch self {
        case .europe: return "api-eu.libreview.io"
        case .unitedStates: return "api-us.libreview.io"
        case .germany: return "api-de.libreview.io"
        case .france: return "api-fr.libreview.io"
        case .japan: return "api-jp.libreview.io"
        case .asiaPacific: return "api-ap.libreview.io"
        case .australia: return "api-au.libreview.io"
        case .canada: return "api-ca.libreview.io"
        }
    }

    var displayName: String {
        switch self {
        case .europe: return "Europe"
        case .unitedStates: return "United States"
        case .germany: return "Germany"
        case .france: return "France"
        case .japan: return "Japan"
        case .asiaPacific: return "Asia-Pacific"
        case .australia: return "Australia"
        case .canada: return "Canada"
        }
    }
}

/// One reading as LibreLinkUp reports it, before normalisation.
struct LibreGlucoseMeasurement: Equatable {
    let mgdl: Double
    let timestamp: Date
    let trendArrow: Int?
    let isHigh: Bool
    let isLow: Bool
}

/// What the API layer can do. Behind a protocol so the source can be tested without a
/// network, and so a change of endpoint stays inside one file.
protocol LibreLinkUpFetching: AnyObject {
    func authenticate(email: String, password: String, region: LibreRegion) async throws -> LibreSession
    func fetchLatest(session: LibreSession, region: LibreRegion) async throws -> LibreGlucoseMeasurement
}

/// The result of a successful sign-in.
struct LibreSession: Equatable {
    let token: String
    let accountID: String
    var patientID: String?

    /// The host this session is valid against, discovered at sign-in. Kept so later
    /// requests do not have to rediscover the region, and so a stored wrong region cannot
    /// send them somewhere the token is not accepted.
    var host: String = LibreLinkUpAPI.globalHost
}

/// Live implementation.
final class LibreLinkUpAPI: LibreLinkUpFetching {

    /// Headers the service expects. Taken from a client that is known to work against
    /// this account today; sending fewer of them produces a 403 or a nonsense status
    /// rather than a useful error.
    ///
    /// `llu.android` is deliberate — `llu.ios` was rejected. The version is bumped by
    /// Abbott periodically and a stale one is the usual cause of a sudden 403 everywhere.
    /// The user agent matters too: URLSession's default is not accepted.
    enum Header {
        static let product = "llu.android"
        static let version = "4.16.0"
        static let userAgent = "LibreLinkUp/4.16.0 (Android; Build 1)"
    }

    /// Region-agnostic entry point.
    ///
    /// Signing in here rather than at a regional host lets the service say where the
    /// account actually lives, which it does with a redirect. That is more reliable than
    /// asking the user to pick correctly: the wrong choice fails as an authentication
    /// error with nothing pointing at the region.
    static let globalHost = "api.libreview.io"

    /// Guards the redirect chain. One hop is normal; more than a couple means something
    /// is wrong and looping would not help.
    private static let maximumRedirects = 3

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    private func request(_ path: String, host: String, token: String?, accountID: String?) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://\(host)\(path)")!)

        // The full set. Omitting any of these has been observed to produce a 403 or a
        // misleading status rather than a useful error.
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("gzip", forHTTPHeaderField: "accept-encoding")
        request.setValue("no-cache", forHTTPHeaderField: "cache-control")
        request.setValue("no-cache", forHTTPHeaderField: "pragma")
        request.setValue("Keep-Alive", forHTTPHeaderField: "connection")
        request.setValue(Header.product, forHTTPHeaderField: "product")
        request.setValue(Header.version, forHTTPHeaderField: "version")
        request.setValue(Header.userAgent, forHTTPHeaderField: "user-agent")

        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let accountID {
            // The API expects the account id as a SHA-256 hex digest in this header.
            request.setValue(Self.sha256Hex(accountID), forHTTPHeaderField: "account-id")
        }
        return request
    }

    func authenticate(email: String, password: String, region: LibreRegion) async throws -> LibreSession {
        // Start where the service can tell us where the account lives. The stored region
        // is only a hint: if it is wrong, the redirect corrects it and the correct host
        // comes back in the session, so the user is never asked to guess again.
        try await authenticate(email: email, password: password,
                               host: Self.globalHost, redirectsRemaining: Self.maximumRedirects)
    }

    private func authenticate(email: String, password: String,
                              host: String, redirectsRemaining: Int) async throws -> LibreSession {

        var request = self.request("/llu/auth/login", host: host, token: nil, accountID: nil)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["email": email, "password": password]
        )

        let (data, response) = try await session.data(for: request)
        try Self.check(response, data: data)

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GlucoseSourceError.decoding("login response was not an object")
        }

        // The service answers a sign-in in one of four ways, and telling them apart is
        // the difference between a useful message and "something went wrong".
        guard let payload = root["data"] as? [String: Any] else {
            let status = root["status"] as? Int ?? -1
            throw GlucoseSourceError.notAuthenticated(Self.describeLoginStatus(status))
        }

        // 1. The account lives elsewhere. Follow it rather than making the user pick.
        if let redirect = payload["redirect"] as? Bool, redirect,
           let regionCode = payload["region"] as? String {
            guard redirectsRemaining > 0 else {
                throw GlucoseSourceError.notAuthenticated("too many redirects while locating the account")
            }
            let regionalHost = "api-\(regionCode.lowercased()).libreview.io"
            return try await authenticate(email: email, password: password,
                                          host: regionalHost,
                                          redirectsRemaining: redirectsRemaining - 1)
        }

        // 2. Credentials are fine, but something must be accepted first. There is no token
        //    until that happens, and it can only be done in the official app — MedProbe
        //    will not accept terms on anyone's behalf.
        if let step = payload["step"] as? [String: Any], let type = step["type"] as? String {
            switch type {
            case "tou":
                throw GlucoseSourceError.notAuthenticated(
                    "LibreLinkUp needs the terms of use accepted — open the LibreLinkUp app, accept them, then sign in here again"
                )
            case "pp":
                throw GlucoseSourceError.notAuthenticated(
                    "LibreLinkUp needs the privacy policy accepted — open the LibreLinkUp app, accept it, then sign in here again"
                )
            default:
                throw GlucoseSourceError.notAuthenticated(
                    "LibreLinkUp wants something confirmed first (step '\(type)') — open the LibreLinkUp app and complete it"
                )
            }
        }

        // 3. A token, which is the only case that continues.
        guard let auth = payload["authTicket"] as? [String: Any],
              let token = auth["token"] as? String else {
            throw GlucoseSourceError.decoding("sign-in returned neither a token nor a reason")
        }
        guard let user = payload["user"] as? [String: Any],
              let accountID = user["id"] as? String else {
            throw GlucoseSourceError.decoding("no account id in login response")
        }

        return LibreSession(token: token, accountID: accountID, patientID: nil, host: host)
    }

    func fetchLatest(session libreSession: LibreSession, region: LibreRegion) async throws -> LibreGlucoseMeasurement {
        // The host comes from the session, so a redirect discovered at sign-in keeps
        // applying to every later request.
        let patientID = try await resolvePatientID(session: libreSession)

        let request = request("/llu/connections/\(patientID)/graph",
                              host: libreSession.host,
                              token: libreSession.token,
                              accountID: libreSession.accountID)

        let (data, response) = try await session.data(for: request)
        try Self.check(response, data: data)

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any],
              let connection = payload["connection"] as? [String: Any],
              let measurement = connection["glucoseMeasurement"] as? [String: Any] else {
            throw GlucoseSourceError.decoding("no glucose measurement in graph response")
        }

        return try Self.parse(measurement)
    }

    /// Finds the followed patient. A follower account can watch several people; without a
    /// stored choice the first connection is used.
    private func resolvePatientID(session libreSession: LibreSession) async throws -> String {
        if let existing = libreSession.patientID { return existing }

        let request = request("/llu/connections",
                              host: libreSession.host,
                              token: libreSession.token,
                              accountID: libreSession.accountID)

        let (data, response) = try await session.data(for: request)
        try Self.check(response, data: data)

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let connections = root["data"] as? [[String: Any]] else {
            throw GlucoseSourceError.decoding("connection list was not an array")
        }
        guard let first = connections.first, let patientID = first["patientId"] as? String else {
            throw GlucoseSourceError.noReadingAvailable
        }
        return patientID
    }

    // MARK: - parsing

    static func parse(_ measurement: [String: Any]) throws -> LibreGlucoseMeasurement {
        guard let mgdl = measurement["ValueInMgPerDl"] as? Double
                ?? (measurement["ValueInMgPerDl"] as? Int).map(Double.init) else {
            throw GlucoseSourceError.decoding("measurement has no ValueInMgPerDl")
        }
        guard let stamp = measurement["FactoryTimestamp"] as? String
                ?? measurement["Timestamp"] as? String else {
            throw GlucoseSourceError.decoding("measurement has no timestamp")
        }
        guard let timestamp = parseTimestamp(stamp) else {
            throw GlucoseSourceError.decoding("could not read timestamp '\(stamp)'")
        }

        return LibreGlucoseMeasurement(
            mgdl: mgdl,
            timestamp: timestamp,
            trendArrow: measurement["TrendArrow"] as? Int,
            isHigh: (measurement["isHigh"] as? Bool) ?? false,
            isLow: (measurement["isLow"] as? Bool) ?? false
        )
    }

    /// LibreLinkUp reports UTC in a US-style format. Parsing is pinned to a fixed locale
    /// and time zone so a phone in another locale does not silently misread it.
    static func parseTimestamp(_ string: String) -> Date? {
        for format in ["M/d/yyyy h:mm:ss a", "M/d/yyyy H:mm:ss"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = format
            if let date = formatter.date(from: string) { return date }
        }
        return ISO8601DateFormatter().date(from: string)
    }

    /// LibreLinkUp's trend arrows, 1 (falling fast) to 5 (rising fast).
    static func trend(fromArrow arrow: Int?) -> GlucoseTrend {
        switch arrow {
        case 1: return .fallingQuickly
        case 2: return .falling
        case 3: return .steady
        case 4: return .rising
        case 5: return .risingQuickly
        default: return .unknown
        }
    }

    // MARK: - helpers

    private static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw GlucoseSourceError.transport("response was not HTTP")
        }
        switch http.statusCode {
        case 200...299:
            return
        case 401:
            throw GlucoseSourceError.notAuthenticated("HTTP 401 — email or password rejected")
        case 403:
            // Not a credential problem: the service refuses the client itself, almost
            // always because the product/version headers no longer match what it expects.
            throw GlucoseSourceError.notAuthenticated(
                "HTTP 403 — service refused this client (product \(Header.product), version \(Header.version)); the version may need updating"
            )
        case 429:
            let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init) ?? 60
            throw GlucoseSourceError.rateLimited(retryAfter: retryAfter)
        default:
            throw GlucoseSourceError.transport("HTTP \(http.statusCode)")
        }
    }

    /// Turns the service's own status code into something actionable.
    ///
    /// These are not HTTP codes. 2 is by far the most common and means exactly what it
    /// says — the email or password is wrong — so it must not be reported as a region
    /// problem, which is what an earlier version did.
    static func describeLoginStatus(_ status: Int) -> String {
        switch status {
        case 2:
            return "email or password is wrong (status 2). Note these are LibreLinkUp credentials, which are a separate account from the Libre app itself"
        case 4:
            return "account needs something accepted in the LibreLinkUp app first (status 4)"
        case 429:
            return "too many sign-in attempts (status 429) — wait a few minutes"
        default:
            return "sign-in refused (status \(status))"
        }
    }

    static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
