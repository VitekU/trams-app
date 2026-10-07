//
//  ContentView.swift
//  trams-app
//
//  Created by Vít Ungermann on 06.10.2026.
//

import SwiftUI

struct ContentView: View {
    @State private var stops: [StopDepartures] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastUpdated: Date?

    private static let updatedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Departures")
                .toolbar {
                    Button {
                        Task { await load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
        }
        .task {
            if stops.isEmpty {
                await load()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage, stops.isEmpty {
            ErrorView(message: errorMessage) {
                Task { await load() }
            }
        } else if stops.isEmpty {
            if isLoading {
                ProgressView("Loading departures…")
            } else {
                ContentUnavailableView(
                    "No departures",
                    systemImage: "tram",
                    description: Text("There are no departures to show right now.")
                )
            }
        } else {
            List {
                ForEach(stops) { stop in
                    StopTile(stop: stop)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                if let lastUpdated {
                    Text("Updated \(Self.updatedFormatter.string(from: lastUpdated))")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
            .refreshable {
                await load()
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            stops = try await APIClient.shared.fetchDepartures()
            lastUpdated = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct StopTile: View {
    let stop: StopDepartures

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 6) {
                    ForEach(stop.sortedLines, id: \.self) { line in
                        Text(line)
                            .font(.headline.monospaced())
                            .foregroundStyle(.primary)
                            .frame(minWidth: 36, minHeight: 36)
                            .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(stop.stopName)
                        .font(.headline)

                    if !headsigns.isEmpty {
                        Text(headsigns)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }

            VStack(spacing: 8) {
                ForEach(stop.sortedLines, id: \.self) { line in
                    ForEach(stop.departures[line] ?? []) { departure in
                        DepartureRow(departure: departure)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var headsigns: String {
        var seen = Set<String>()
        let all = stop.sortedLines.flatMap { line in
            (stop.departures[line] ?? []).compactMap(\.headsign)
        }
        return all.filter { seen.insert($0).inserted }.joined(separator: " · ")
    }
}

private struct DepartureRow: View {
    let departure: Departure

    var body: some View {
        HStack {
            if let minutes = departure.minutes {
                Text("in \(minutes) min")
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(minutesColor)
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let time = departure.displayTime {
                Text(time)
                    .font(.body.monospacedDigit())
            }
        }
    }

    private var minutesColor: Color {
        guard let delay = departure.delayMinutes else { return .green }
        switch delay {
        case ..<1: return .green
        case 1...5: return .orange
        default: return .red
        }
    }
}

private struct ErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Something went wrong", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                retry()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    ContentView()
}
