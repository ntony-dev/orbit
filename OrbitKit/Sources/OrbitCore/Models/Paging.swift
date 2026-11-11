public struct PageRequest: Hashable, Codable, Sendable {
    public var offset: Int
    public var limit: Int

    public init(offset: Int = 0, limit: Int = 50) {
        self.offset = offset
        self.limit = limit
    }
}

public struct Page<Item> {
    public var items: [Item]
    public var offset: Int
    public var total: Int?
    public var hasMore: Bool

    public init(items: [Item], offset: Int, total: Int? = nil, hasMore: Bool) {
        self.items = items
        self.offset = offset
        self.total = total
        self.hasMore = hasMore
    }

    public func nextRequest(limit: Int) -> PageRequest? {
        hasMore ? PageRequest(offset: offset + items.count, limit: limit) : nil
    }
}

extension Page: Sendable where Item: Sendable {}
extension Page: Equatable where Item: Equatable {}
extension Page: Hashable where Item: Hashable {}
extension Page: Codable where Item: Codable {}
