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
            let (data, response) = try await session.data(for: request)
            return InternetProbeValidator.isSuccessful(data: data, response: response)
        } catch {
            return false
        }
    }
}

enum InternetProbeValidator {
    private static let successMarker = "<body>success</body>"

    static func isSuccessful(data: Data, response: URLResponse) -> Bool {
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              http.url?.host?.caseInsensitiveCompare("captive.apple.com") == .orderedSame,
              let body = String(data: data, encoding: .utf8)
        else { return false }

        return body.range(of: successMarker, options: .caseInsensitive) != nil
    }
}
