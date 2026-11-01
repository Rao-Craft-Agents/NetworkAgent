import Foundation

/// What a call can say instead of writing.
public enum NetworkError: Error, Equatable, CustomStringConvertible {
    /// A line that is not understood, and why.
    case line(String, String)
    /// Everything the call cannot honour, one sentence each, so all are fixed in one call.
    case refused([String])
    /// A call with no endpoints, no entities and no feeds.
    case nothing

    public var description: String {
        switch self {
        case .line(let line, let reason): return "`\(line)`: \(reason)"
        case .refused(let reasons):
            let count = reasons.count == 1 ? "1 thing" : "\(reasons.count) things"
            return "\(count) in the call cannot be honoured, so nothing was written:\n" + reasons.map { "- \($0)" }.joined(separator: "\n")
        case .nothing: return "the call gives no `endpoints`, no `entities` and no `feeds`: say each endpoint as one line"
        }
    }
}
