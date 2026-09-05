//
//  PacketRecorder.swift
//  MedProbe
//
//  Append-only capture of every notification, persisted to disk so a recording
//  survives backgrounding, foregrounding and app relaunch.
//
//  Storage is JSON Lines: one self-contained JSON object per line, appended as it
//  happens. A truncated final line from an unexpected termination costs one record,
//  not the whole file — which matters when the point of the exercise is to leave the
//  phone recording for half an hour.
//

import Foundation
import OSLog

/// Records notifications and manually marked EasyPatch readings, and exports them as CSV.
///
/// Main-queue confined, like the rest of the BLE path.
final class PacketRecorder: ObservableObject {

    /// Rows held for the live view. The file on disk is the complete record.
    @Published private(set) var recentRecords: [PacketRecord] = []

    /// Total rows written this session plus whatever was already in the file.
    @Published private(set) var recordCount: Int = 0

    /// Set when writing fails, so a silent loss of data cannot go unnoticed.
    @Published private(set) var storageError: String?

    /// How many rows the live view keeps. The file is not truncated.
    private let liveWindow = 40

    /// Safety valve: a runaway stream must not fill the device.
    private let maximumRecords = 200_000

    private let logger = Logger(subsystem: MedProbeConstants.logSubsystem, category: "recorder")
    private let fileManager = FileManager.default
    private var fileHandle: FileHandle?

    // JSONEncoder's built-in .iso8601 strategy writes whole seconds only — it does not
    // include fractional seconds. Using it silently truncated every recorded timestamp to
    // the second, which defeats the point of recording milliseconds in the first place:
    // several packets routinely land inside one second and their order matters.
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(PacketRecord.timestampFormatter.string(from: date))
        }
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = PacketRecord.parseTimestamp(string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unrecognised timestamp: \(string)"
                )
            }
            return date
        }
        return decoder
    }()

    /// Capture file, in Documents. With UIFileSharingEnabled set, this is also visible in
    /// Files.app under On My iPhone → MedProbe, so a session can be retrieved without the
    /// export button — which matters if the app is killed mid-recording.
    var captureURL: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("medprobe-capture.jsonl")
    }

    // MARK: - lifecycle

    init() {
        openFile()
        loadExistingCount()
    }

    deinit {
        try? fileHandle?.close()
    }

    private func openFile() {
        if !fileManager.fileExists(atPath: captureURL.path) {
            fileManager.createFile(atPath: captureURL.path, contents: nil)
        }

        do {
            let handle = try FileHandle(forWritingTo: captureURL)
            try handle.seekToEnd()
            fileHandle = handle
            logger.info("Capture file open at \(self.captureURL.lastPathComponent, privacy: .public)")
        } catch {
            storageError = error.localizedDescription
            logger.error("Could not open capture file: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Counts what a previous run left behind, so the UI total is honest after a relaunch.
    private func loadExistingCount() {
        guard let contents = try? String(contentsOf: captureURL, encoding: .utf8) else { return }
        recordCount = contents.split(separator: "\n").count
    }

    // MARK: - recording

    func record(characteristic: String, data: Data, at timestamp: Date = Date()) {
        append(.packet(timestamp: timestamp, characteristic: characteristic, data: data))
    }

    /// Stores a glucose value the user read from EasyPatch, with the exact moment they marked it.
    ///
    /// This is reference data for offline correlation only. Nothing in MedProbe reads it back,
    /// and it never influences decoding.
    func recordGroundTruth(mmoll: Double, at timestamp: Date = Date()) {
        append(.groundTruth(timestamp: timestamp, mmoll: mmoll))
        logger.info("Ground truth marked: \(mmoll, privacy: .public) mmol/L")
    }

    private func append(_ record: PacketRecord) {
        guard recordCount < maximumRecords else {
            if storageError == nil {
                storageError = "Capture full at \(maximumRecords) records; stopped recording."
                logger.error("Capture limit reached, no longer recording")
            }
            return
        }

        recentRecords.insert(record, at: 0)
        if recentRecords.count > liveWindow {
            recentRecords.removeLast(recentRecords.count - liveWindow)
        }
        recordCount += 1

        guard let fileHandle else { return }

        do {
            var line = try encoder.encode(record)
            line.append(0x0A)   // newline
            try fileHandle.write(contentsOf: line)
            // Flush per record: the phone will be left recording unattended, and a
            // buffered tail lost to a background kill is exactly the data we care about.
            try fileHandle.synchronize()
            storageError = nil
        } catch {
            storageError = error.localizedDescription
            logger.error("Failed to append record: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - export

    /// Reads the whole capture back from disk, oldest first.
    func loadAllRecords() -> [PacketRecord] {
        guard let contents = try? String(contentsOf: captureURL, encoding: .utf8) else { return [] }

        return contents
            .split(separator: "\n")
            .compactMap { line in
                guard let data = line.data(using: .utf8) else { return nil }
                // A partially written final line is skipped rather than failing the export.
                return try? decoder.decode(PacketRecord.self, from: data)
            }
    }

    /// Writes the capture out as CSV and returns the file to share.
    func exportCSV() throws -> URL {
        let records = loadAllRecords()
        let csv = PacketRecord.csv(from: records)

        let stamp = PacketRecord.timestampFormatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("medprobe-capture-\(stamp).csv")

        try csv.write(to: url, atomically: true, encoding: .utf8)
        logger.info("Exported \(records.count, privacy: .public) records")
        return url
    }

    /// Starts a fresh capture. Destructive, so the UI asks first.
    func clear() {
        try? fileHandle?.close()
        fileHandle = nil
        try? fileManager.removeItem(at: captureURL)

        recentRecords.removeAll()
        recordCount = 0
        storageError = nil

        openFile()
        logger.info("Capture cleared")
    }
}
