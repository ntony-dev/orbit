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
    // Set when entries the source returned were dropped (null, local or unsupported items), so paging neither
    // repeats nor skips them; nil means the next page starts right after `items`.
    public var nextOffset: Int?

    public init(items: [Item], offset: Int, total: Int? = nil, hasMore: Bool, nextOffset: Int? = nil) {
        self.items = items
        self.offset = offset
        self.total = total
        self.hasMore = hasMore
        self.nextOffset = nextOffset
    }

    public func nextRequest(limit: Int) -> PageRequest? {
        hasMore ? PageRequest(offset: nextOffset ?? offset + items.count, limit: limit) : nil
    }
}

extension Page: Sendable where Item: Sendable {}
extension Page: Equatable where Item: Equatable {}
extension Page: Hashable where Item: Hashable {}
extension Page: Codable where Item: Codable {}
