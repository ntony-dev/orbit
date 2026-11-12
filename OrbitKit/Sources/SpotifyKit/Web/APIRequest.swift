import Foundation

struct APIRequest: Sendable {
    enum Method: String, Sendable {
        case get = "GET", put = "PUT", post = "POST", delete = "DELETE"
    }

    // Decides how an ambiguous 403 or 404 is read, because Spotify reuses those codes for unrelated causes.
    // `playContext` is a player command naming a context that may no longer exist.
    enum Kind: Sendable {
        case player, playContext, playlistItems, other
    }

    static let baseURL = URL(string: "https://api.spotify.com/v1")!

    var method: Method
    var path: String
    var query: [(String, String)] = []
    var body: Data?
    var kind: Kind = .other

    init(_ method: Method, _ path: String, query: [(String, String?)] = [], body: Data? = nil, kind: Kind = .other) {
        self.method = method
        self.path = path
        self.query = query.compactMap { name, value in value.map { (name, $0) } }
        self.body = body
        self.kind = kind
    }

    init(_ method: Method, _ path: String, query: [(String, String?)] = [], json: some Encodable, kind: Kind = .other) {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.init(method, path, query: query, body: try? encoder.encode(json), kind: kind)
    }

    func urlRequest(token: String) -> URLRequest {
        // `path` is already percent-encoded by `pathSegment`; URL.appending(path:) would encode it a second time.
        var components = URLComponents(url: Self.baseURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedPath += path
        if !query.isEmpty { components.percentEncodedQuery = FormEncoding.encode(query) }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method.rawValue
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if method != .get {
            // Spotify has answered 411 Length Required to body-less PUT and POST commands.
            request.httpBody = Data()
        }
        return request
    }

    // nil for values that would not stay one segment: empty, or a dot segment that resolves to the parent path.
    static func pathSegment(_ value: String) -> String? {
        guard !["", ".", ".."].contains(value) else { return nil }
        return FormEncoding.escape(value)
    }
}
