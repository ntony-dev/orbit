import Foundation
import OrbitCore

protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws(OrbitError) -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    init() {
        // Ephemeral with no cache or cookie storage, so tokens and personal responses never touch disk.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    func send(_ request: URLRequest) async throws(OrbitError) -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw OrbitError.unexpected(detail: "Spotify returned a non-HTTP response.")
            }
            return (data, http)
        } catch let error as OrbitError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw .cancelled
        } catch is CancellationError {
            throw .cancelled
        } catch let error as URLError {
            // The code alone: URLError descriptions can include the request URL.
            throw .network(detail: "URLError \(error.code.rawValue)")
        } catch {
            throw .network(detail: "The request failed.")
        }
    }
}

enum RetryAfter {
    // Spotify sends seconds; the HTTP-date form is accepted too because the header allows it.
    static func parse(_ value: String?, now: Date) -> TimeInterval? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if let seconds = TimeInterval(value) { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSince(now)) }
    }
}
