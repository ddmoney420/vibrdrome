import Foundation

enum SubsonicError: LocalizedError {
    case httpError(Int)
    case apiError(code: Int, message: String)
    case noServerConfigured
    case decodingError(Error)
    case networkUnavailable
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .httpError(let code): "HTTP error \(code)"
        case .apiError(_, let message): message
        case .noServerConfigured: "No server configured"
        case .decodingError(let error): "Decoding error: \(error.localizedDescription)"
        case .networkUnavailable: "Network unavailable"
        case .invalidURL: "Invalid server URL"
        }
    }
}
