import Foundation
import TapPonyKit

/// Outcome of one send, shown on the Scan tab and later in History.
struct SendResult: Equatable {
    var status: Int?
    var latencyMs: Int
    var responseBody: String?
    var error: String?
    var ok: Bool { (status ?? 0) >= 200 && (status ?? 0) < 300 }
}

/// Sends a PreparedRequest with an ephemeral URLSession. Redirects are refused
/// unless the profile opts in, and then only to the same scheme and host, each
/// hop re-checked by the host policy.
final class Sender: NSObject, URLSessionTaskDelegate {

    private static let maxBody = 64 * 1024

    func send(_ req: PreparedRequest, allowLocalHttp: Bool) async -> SendResult {
        let started = Date()
        func elapsed() -> Int { Int(Date().timeIntervalSince(started) * 1000) }
        guard let url = URL(string: req.url) else { return SendResult(status: nil, latencyMs: 0, error: "malformedUrl") }
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: TimeInterval(req.timeoutSeconds))
        r.httpMethod = req.method
        for (n, v) in req.headers { r.addValue(v, forHTTPHeaderField: n) }
        if req.method != "GET" && req.method != "DELETE" { r.httpBody = Data((req.body ?? "").utf8) }

        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = TimeInterval(req.timeoutSeconds)
        let delegate = RedirectPolicy(follow: req.followRedirects, allowLocalHttp: allowLocalHttp)
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (data, response) = try await session.data(for: r)
            let status = (response as? HTTPURLResponse)?.statusCode
            let body = String(decoding: data.prefix(Self.maxBody), as: UTF8.self)
            return SendResult(status: status, latencyMs: elapsed(), responseBody: body, error: nil)
        } catch {
            return SendResult(status: nil, latencyMs: elapsed(), responseBody: nil, error: (error as NSError).localizedDescription)
        }
    }
}

private final class RedirectPolicy: NSObject, URLSessionTaskDelegate {
    let follow: Bool
    let allowLocalHttp: Bool
    private var hops = 0

    init(follow: Bool, allowLocalHttp: Bool) {
        self.follow = follow
        self.allowLocalHttp = allowLocalHttp
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard follow, hops < 5, let from = task.originalRequest?.url, let to = request.url,
              from.scheme?.lowercased() == to.scheme?.lowercased(),
              from.host?.lowercased() == to.host?.lowercased(),
              HostPolicy.check(to.absoluteString, allowLocalHttp: allowLocalHttp).allowed else {
            completionHandler(nil)
            return
        }
        hops += 1
        completionHandler(request)
    }
}
