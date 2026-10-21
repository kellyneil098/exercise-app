import Foundation

/// Transport for `/sync/push` and `/sync/pull` plus auth/invite endpoints (§9–§10).
public struct APIClient: Sendable {
    public var baseURL: URL
    public var session: URLSession
    public var token: @Sendable () -> String?

    public init(baseURL: URL, session: URLSession = .shared, token: @escaping @Sendable () -> String?) {
        self.baseURL = baseURL; self.session = session; self.token = token
    }

    public enum APIError: Error, Equatable { case unauthorized, http(Int), transport }

    func request(_ method: String, _ path: String, body: Data? = nil, auth: Bool = true) async throws -> Data {
        var req = URLRequest(url: baseURL.appending(path: path))
        req.httpMethod = method
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if auth, let t = token() { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(for: req) } catch { throw APIError.transport }
        guard let http = resp as? HTTPURLResponse else { throw APIError.transport }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
        return data
    }

    public func get<T: Decodable>(_ path: String, as: T.Type) async throws -> T {
        try JSONDecoder.store.decode(T.self, from: try await request("GET", path))
    }

    public func post<B: Encodable, T: Decodable>(_ path: String, _ body: B, as: T.Type, auth: Bool = true) async throws -> T {
        try JSONDecoder.store.decode(T.self, from: try await request("POST", path, body: try JSONEncoder.store.encode(body), auth: auth))
    }
}

public struct UserDTO: Codable, Sendable, Equatable {
    public var id: String
    public var email: String?
    public var displayName: String
    enum CodingKeys: String, CodingKey { case id, email, displayName = "display_name" }
}

public struct TokenDTO: Codable, Sendable { public var token: String; public var user: UserDTO }

public struct InviteDTO: Codable, Sendable {
    public var code: String
    public var expiresAt: Date
    enum CodingKeys: String, CodingKey { case code, expiresAt = "expires_at" }
}

public struct SharesDTO: Codable, Sendable {
    public var iCanView: [UserDTO]
    public var canViewMe: [UserDTO]
    enum CodingKeys: String, CodingKey { case iCanView = "i_can_view", canViewMe = "can_view_me" }
}

struct PushBody: Encodable {
    struct Rec: Encodable {
        var id: String; var table: String; var op: String; var payload: RawJSON; var updated_at: Date
    }
    var records: [Rec]
}

struct RawJSON: Encodable {
    let json: String
    func encode(to encoder: Encoder) throws {
        // Payload is already JSON text; re-decode to a generic object so it nests correctly.
        let obj = try JSONSerialization.jsonObject(with: Data(json.utf8))
        try (obj as? [String: Any]).map { try JSONValue($0).encode(to: encoder) }
    }
}

/// Minimal JSON tree for passing opaque payloads through Codable.
indirect enum JSONValue: Codable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    init(_ any: Any) throws {
        switch any {
        case is NSNull: self = .null
        case let b as Bool where !(any is NSNumber && CFGetTypeID(any as CFTypeRef) != CFBooleanGetTypeID()): self = .bool(b)
        case let n as NSNumber: self = .number(n.doubleValue)
        case let s as String: self = .string(s)
        case let a as [Any]: self = .array(try a.map(JSONValue.init))
        case let o as [String: Any]: self = .object(try o.mapValues(JSONValue.init))
        default: throw EncodingError.invalidValue(any, .init(codingPath: [], debugDescription: "unsupported"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): if n == n.rounded(), abs(n) < 1e15 { try c.encode(Int64(n)) } else { try c.encode(n) }
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
}

struct PushResponse: Decodable { var accepted: Int; var ignored: Int; var cursor: Int }

struct PullResponse: Decodable {
    struct Rec: Decodable {
        var id: String; var user_id: String; var table: String; var payload: JSONValue
        var updated_at: Date; var deleted: Bool; var seq: Int
    }
    var records: [Rec]
    var cursor: Int
    var has_more: Bool
}

/// Drains the outbox and pulls since the stored cursor. Safe to call from a background task repeatedly.
public struct SyncClient: Sendable {
    public var api: APIClient
    public var store: WorkoutStore
    public var batchSize = 200

    public init(api: APIClient, store: WorkoutStore) { self.api = api; self.store = store }

    public struct Result: Sendable, Equatable { public var pushed: Int; public var pulled: Int }

    @discardableResult
    public func sync() async throws -> Result {
        let pushed = try await push()
        let pulled = try await pull()
        return Result(pushed: pushed, pulled: pulled)
    }

    public func push() async throws -> Int {
        var total = 0
        while true {
            let rows = try store.pendingOutbox(limit: batchSize)
            if rows.isEmpty { return total }
            let body = PushBody(records: rows.map {
                .init(id: $0.id, table: $0.tableName, op: $0.op, payload: RawJSON(json: $0.payload), updated_at: $0.createdAt)
            })
            _ = try await api.post("/sync/push", body, as: PushResponse.self)
            try store.clearOutbox(ids: rows.map(\.id))
            total += rows.count
        }
    }

    public func pull() async throws -> Int {
        var total = 0
        while true {
            let page = try await api.get("/sync/pull?since=\(store.pullCursor)", as: PullResponse.self)
            for r in page.records {
                let payload = try JSONEncoder.store.encode(r.payload)
                try store.apply(pulled: PulledRecord(id: r.id, userId: r.user_id, table: r.table, payload: payload,
                                                     updatedAt: r.updated_at, deleted: r.deleted, seq: r.seq))
            }
            total += page.records.count
            try store.setPullCursor(page.cursor)
            if !page.has_more { return total }
        }
    }
}
