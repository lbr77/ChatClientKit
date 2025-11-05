import Foundation

public enum OAuthError: Error, LocalizedError {
    case invalidConfiguration
    case invalidAuthorizationURL
    case invalidRedirectURI
    case invalidClientCredentials
    case invalidAuthorizationCode
    case invalidAccessToken
    case invalidRefreshToken
    case tokenExpired
    case networkError(Error)
    case serverError(String)
    case unknownError
    case pkceError(PKCEError)
    case stateValidationFailed
    case sessionExpired
    
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Invalid OAuth configuration"
        case .invalidAuthorizationURL:
            return "Invalid authorization URL"
        case .invalidRedirectURI:
            return "Invalid redirect URI"
        case .invalidClientCredentials:
            return "Invalid client credentials"
        case .invalidAuthorizationCode:
            return "Invalid authorization code"
        case .invalidAccessToken:
            return "Invalid access token"
        case .invalidRefreshToken:
            return "Invalid refresh token"
        case .tokenExpired:
            return "Token has expired"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let message):
            return "Server error: \(message)"
        case .unknownError:
            return "Unknown error occurred"
        case .pkceError(let pkceError):
            return "PKCE error: \(pkceError)"
        case .stateValidationFailed:
            return "State validation failed"
        case .sessionExpired:
            return "OAuth session has expired"
        }
    }
}