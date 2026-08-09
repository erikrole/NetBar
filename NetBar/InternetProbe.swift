import Foundation

actor InternetProbe {
    private let session: URLSession
    private let endpoint = URL(string: "https://captive.apple.com/hotspot-detect.html")!

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 3
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        session = URLSession(configuration: configuration)
    }

    func check() async -> Bool {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("NetBar/1", forHTTPHeaderField: "User-Agent")
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200 ..< 400).contains(http.statusCode)
        } catch {
            return false
        }
    }
}
