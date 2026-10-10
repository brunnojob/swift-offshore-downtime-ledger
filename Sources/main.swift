import Foundation

enum Failure: Error, CustomStringConvertible {
    case invalid(String)
    var description: String { switch self { case .invalid(let message): return message } }
}
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw Failure.invalid(message) }
}
func numeric(_ value: String) throws -> Double {
    guard let parsed = Double(value), parsed.isFinite else { throw Failure.invalid("Finite number required") }
    return parsed
}
func input(_ columns: Int) throws -> [[String]] {
    var rows: [[String]] = []
    while let line = readLine() {
        try require(rows.count < 100000, "Input capacity exceeded")
        try require(line.utf8.count <= 8192, "Input record too large")
        let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        try require(fields.count == columns && fields.allSatisfy { !$0.isEmpty }, "Invalid CSV row")
        rows.append(fields)
    }
    try require(!rows.isEmpty, "Missing input")
    return rows
}
func output<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    guard let text = String(data: data, encoding: .utf8) else { throw Failure.invalid("Encoding failed") }
    print(text)
}

struct Interval { let asset: String; let start: Double; let end: Double; let cause: String }
struct Availability: Codable { let asset: String; let downtime: Double; let observed: Double; let availability: Double; let mergedOutages: Int }
func availability(_ intervals: [Interval], horizon: Double) throws -> [Availability] {
    try require(horizon > 0, "Positive observation horizon required")
    for interval in intervals { try require(interval.start >= 0 && interval.end > interval.start && interval.end <= horizon, "Outage outside observation horizon") }
    let groups = Dictionary(grouping: intervals, by: { $0.asset })
    return groups.keys.sorted().map { asset in
        let ordered = groups[asset]!.sorted { $0.start < $1.start }
        var total = 0.0, start = ordered[0].start, end = ordered[0].end, count = 1
        for interval in ordered.dropFirst() {
            if interval.start <= end { end = max(end, interval.end) }
            else { total += end - start; start = interval.start; end = interval.end; count += 1 }
        }
        total += end - start
        return Availability(asset: asset, downtime: total, observed: horizon, availability: 1 - total / horizon, mergedOutages: count)
    }
}
func test() throws {
    let a = try availability([Interval(asset: "A", start: 1, end: 4, cause: "trip"), Interval(asset: "A", start: 3, end: 6, cause: "power"), Interval(asset: "A", start: 8, end: 9, cause: "repair")], horizon: 10)
    try require(a[0].downtime == 6 && a[0].mergedOutages == 2 && abs(a[0].availability - 0.4) < 1e-12, "Interval union mismatch")
    let adjacent = try availability([Interval(asset: "A", start: 0, end: 1, cause: "x"), Interval(asset: "A", start: 1, end: 2, cause: "y")], horizon: 10)
    try require(adjacent[0].mergedOutages == 1, "Adjacent outage mismatch")
}
func run() throws {
    let intervals = try input(4).map { Interval(asset: $0[0], start: try numeric($0[1]), end: try numeric($0[2]), cause: $0[3]) }
    for result in try availability(intervals, horizon: 24) { try output(result) }
}

do {
    try require(CommandLine.arguments.count == 1 || Array(CommandLine.arguments.dropFirst()) == ["--self-test"], "Unsupported command arguments")
    if Array(CommandLine.arguments.dropFirst()) == ["--self-test"] { try test(); print("Tests passed") }
    else { try run() }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(2)
}
