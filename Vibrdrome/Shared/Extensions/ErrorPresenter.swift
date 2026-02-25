import Foundation

enum ErrorPresenter {
    static func userMessage(for error: Error) -> String {
        if let subsonicError = error as? SubsonicError {
            return message(for: subsonicError)
        }
        if let urlError = error as? URLError {
            return message(for: urlError)
        }
        return "Something went wrong. Please try again."
    }

    private static func message(for error: SubsonicError) -> String {
        switch error {
        case .httpError(let code):
            return httpMessage(for: code)
        case .apiError(let code, let message):
            return apiMessage(for: code, message: message)
        case .noServerConfigured:
            return "No server configured. Add a server in Settings."
        case .decodingError:
            return "Unexpected response from server. It may be incompatible."
        case .networkUnavailable:
            return "No network connection. Check your internet and try again."
        case .invalidURL:
            return "Invalid server URL. Check your server address."
        }
    }

    private static func httpMessage(for code: Int) -> String {
        switch code {
        case 401: return "Authentication failed. Check your credentials."
        case 403: return "Access denied. Your account may not have permission."
        case 404: return "The requested item was not found on the server."
        case 500...599: return "The server encountered an error. Please try again later."
        default: return "Server returned an error (HTTP \(code))."
        }
    }

    private static let apiMessages: [Int: String] = [
        10: "Required parameter is missing.",
        20: "Server version is incompatible with this app.",
        30: "Server version is too old for this feature.",
        40: "Wrong username or password.",
        41: "Token authentication not supported. Check server settings.",
        50: "You don't have permission for this action.",
        60: "Trial period has expired.",
        70: "The requested item was not found.",
    ]

    private static func apiMessage(for code: Int, message: String) -> String {
        if let known = apiMessages[code] {
            return known
        }
        return message.isEmpty ? "Server error." : message
    }

    private static func message(for error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet:
            return "No internet connection."
        case .timedOut:
            return "Connection timed out. The server may be unreachable."
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return "Cannot reach the server. Check the address and try again."
        case .networkConnectionLost:
            return "Network connection was lost. Please try again."
        case .secureConnectionFailed:
            return "Secure connection failed. Check your server's SSL certificate."
        case .cancelled:
            return "Request was cancelled."
        default:
            return "Network error. Please check your connection and try again."
        }
    }
}
