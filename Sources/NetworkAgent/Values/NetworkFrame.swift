import Foundation

/// What a run says as it goes.
public enum NetworkFrame: Sendable {
    /// The lines were read: how many endpoints and types the package holds.
    case read(endpoints: Int, types: Int)
    /// The files are written.
    case written(NetworkResult)

    public var result: NetworkResult? {
        if case .written(let result) = self { return result }
        return nil
    }
}
