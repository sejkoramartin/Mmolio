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
}

/// Live implementation.
final class LibreLinkUpAPI: LibreLinkUpFetching {

    /// Abbott's service rejects unknown clients; these headers mirror what the official
    /// mobile app sends. They are not a secret and contain nothing user-specific.
    private enum Header {
        static let product = "llu.ios"
        static let version = "4.12.0"
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    private func request(_ path: String, region: LibreRegion, token: String?, accountID: String?) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://\(region.host)\(path)")!)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Header.product, forHTTPHeaderField: "product")
        request.setValue(Header.version, forHTTPHeaderField: "version")

        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let accountID {
            // The API expects the account id as a SHA-256 hex digest in this header.
            request.setValue(Self.sha256Hex(accountID), forHTTPHeaderField: "Account-Id")
        }
        return request
    }

    func authenticate(email: String, password: String, region: LibreRegion) async throws -> LibreSession {
        var request = self.request("/llu/auth/login", region: region, token: nil, accountID: nil)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["email": email, "password": password]
        )

        let (data, response) = try await session.data(for: request)
        try Self.check(response, data: data)

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GlucoseSourceError.decoding("login response was not an object")
        }

        // A non-zero status with no data usually means the region is wrong, which is by
        // far the most common setup mistake — so it is called out rather than surfaced as
        // a generic decoding failure.
        guard let payload = root["data"] as? [String: Any] else {
            let status = root["status"] as? Int ?? -1
            throw GlucoseSourceError.notAuthenticated(
                "sign-in refused (status \(status)); check the account region"
            )
        }

        // Some accounts answer with a redirect to their correct region instead of a token.
        if let redirect = payload["redirect"] as? Bool, redirect {
            let suggested = (payload["region"] as? String) ?? "unknown"
            throw GlucoseSourceError.notAuthenticated("account belongs to region '\(suggested)'")
        }

        guard let auth = payload["authTicket"] as? [String: Any],
              let token = auth["token"] as? String else {
            throw GlucoseSourceError.decoding("no auth ticket in login response")
        }
        guard let user = payload["user"] as? [String: Any],
              let accountID = user["id"] as? String else {
            throw GlucoseSourceError.decoding("no account id in login response")
        }

        return LibreSession(token: token, accountID: accountID, patientID: nil)
    }

    func fetchLatest(session libreSession: LibreSession, region: LibreRegion) async throws -> LibreGlucoseMeasurement {
        let patientID = try await resolvePatientID(session: libreSession, region: region)

        let request = request("/llu/connections/\(patientID)/graph",
                              region: region,
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
    private func resolvePatientID(session libreSession: LibreSession, region: LibreRegion) async throws -> String {
        if let existing = libreSession.patientID { return existing }

        let request = request("/llu/connections",
                              region: region,
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
        case 401, 403:
            throw GlucoseSourceError.notAuthenticated("HTTP \(http.statusCode)")
        case 429:
            let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init) ?? 60
            throw GlucoseSourceError.rateLimited(retryAfter: retryAfter)
        default:
            throw GlucoseSourceError.transport("HTTP \(http.statusCode)")
        }
    }

    static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
