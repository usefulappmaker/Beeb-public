import Foundation
@main struct SearchPerformanceTests {
    static func main() async throws {
        let snapshot = try PropertyListDecoder().decode(CatalogueIndexSnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: "BeebHD/CatalogueSeed.plist")))
        let queries = ["Have", "Have I", "Have I Got", "Have I Got News for You", "Industry", "i", "Planet Earth"]
        let baseline = CommandLine.arguments.contains("--baseline")
        let worker = CatalogueSearchWorker()
        let expectedResults = baseline ? [:] : Dictionary(uniqueKeysWithValues: queries.map { ($0, snapshot.search($0).map(\.id)) })
        let start = Date()
        var count = 0
        for query in queries {
            let expected = expectedResults[query]
            for _ in 0..<6 {
                let result = baseline ? snapshot.search(query) : try await worker.search(query, snapshot: snapshot, revision: 1)
                if let expected { precondition(result.map(\.id) == expected, "Search relevance and ordering must stay identical") }
                count += result.count
            }
        }
        let milliseconds = Date().timeIntervalSince(start) * 1000
        print("\(baseline ? "Baseline" : "Cached worker"): seed=\(snapshot.catalogue.count), 7 input updates x 6 evaluations: \(Int(milliseconds)) ms; matched=\(count)")
        fflush(stdout)
        precondition(milliseconds < 250, "Repeated search work must not cause a one-second input stall")
        let replacement = CatalogueIndexSnapshot(catalogue: [])
        let empty = try await worker.search("Industry", snapshot: replacement, revision: 2)
        precondition(empty.isEmpty, "New catalogue revision invalidates search cache")
        let cancelled = Task { () throws -> [CatalogueShow] in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await worker.search("Industry", snapshot: snapshot, revision: 1)
        }
        cancelled.cancel()
        do { _ = try await cancelled.value; preconditionFailure("Cancelled searches cannot publish") } catch is CancellationError { }
    }
}
