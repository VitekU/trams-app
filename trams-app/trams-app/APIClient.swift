//
//  APIClient.swift
//  trams-app
//

import Foundation

struct StopDepartures: Codable, Identifiable {
    let stopId: String
    let stopName: String
    let departures: [String: [Departure]]

    var id: String { stopId }

    var sortedLines: [String] {
        departures.keys.sorted { lhs, rhs in
            (Int(lhs) ?? .max, lhs) < (Int(rhs) ?? .max, rhs)
        }
    }
}

struct Departure: Codable, Identifiable {
    let scheduled: String?
    let predicted: String?
    let minutes: Int?
    let headsign: String?

    var id: String { "\(scheduled ?? "")-\(predicted ?? "")-\(headsign ?? "")" }

    enum CodingKeys: String, CodingKey {
        case scheduled, predicted, minutes, headsign
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scheduled = try container.decodeIfPresent(String.self, forKey: .scheduled)
        predicted = try container.decodeIfPresent(String.self, forKey: .predicted)
        headsign = try container.decodeIfPresent(String.self, forKey: .headsign)
        if let raw = try? container.decodeIfPresent(String.self, forKey: .minutes) {
            minutes = Int(raw)
        } else {
            minutes = try container.decodeIfPresent(Int.self, forKey: .minutes)
        }
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static func parse(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        return isoFractional.date(from: raw) ?? iso.date(from: raw)
    }

    var displayDate: Date? {
        Self.parse(predicted) ?? Self.parse(scheduled)
    }

    var displayTime: String? {
        displayDate.map { Self.timeFormatter.string(from: $0) }
    }

    var isDelayed: Bool {
        guard let scheduled = Self.parse(scheduled),
              let predicted = Self.parse(predicted) else {
            return false
        }
        return predicted > scheduled.addingTimeInterval(60)
    }
}

enum APIError: LocalizedError {
    case unauthorized
    case server(statusCode: Int, detail: String?)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Invalid or missing API token."
        case .server(let statusCode, let detail):
            let suffix = detail.map { ": \($0)" } ?? ""
            return "Server error \(statusCode)\(suffix)"
        }
    }
}

struct APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    func fetchDepartures() async throws -> [StopDepartures] {
        var request = URLRequest(url: Config.baseURL.appendingPathComponent("departures"))
        request.httpMethod = "GET"
        request.setValue(Config.apiToken, forHTTPHeaderField: "X-API-Key")

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.server(statusCode: -1, detail: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = try? decoder.decode(ServerError.self, from: data).detail
            throw http.statusCode == 401
                ? APIError.unauthorized
                : APIError.server(statusCode: http.statusCode, detail: detail)
        }

        return try decoder.decode([StopDepartures].self, from: data)
    }
}

private struct ServerError: Codable {
    let detail: String?
}
