import OrbitCore

public enum LoadState<Value: Sendable>: Sendable {
    case idle
    case loading
    case loaded(Value)
    case failed(OrbitError)

    public var value: Value? {
        if case .loaded(let value) = self { value } else { nil }
    }

    public var error: OrbitError? {
        if case .failed(let error) = self { error } else { nil }
    }

    public var isLoading: Bool {
        if case .loading = self { true } else { false }
    }
}

extension LoadState: Equatable where Value: Equatable {}
