import Foundation

public struct Runtime {
    public struct Request {
        let payload: Data
        let requestID: String
        let xrayTraceID: String
        let clientContext: String
        let cognitoIdentifier: String
        let functionARN: String
        let deadline: Date
        var remainingTime: Date {
            return Date()
        }
    }
    
    public enum Response {
        case success(payload: Data, contentType: String)
        case failure(errorMessage: String, errorType: String)
        
        private struct RawError: Encodable {
            let errorMessage: String
            let errorType: String
            let stackTrace: [String] = []
        }
        
        public var payload: Data {
            switch self {
            case .success(let payload, _):
                return payload
            case .failure(let errorMessage, let errorType):
                let error = RawError(errorMessage: errorMessage, errorType: errorType)
                return try! JSONEncoder().encode(error)
            }
        }
        
        public var contentType: String {
            switch self {
            case .success(_, let contentType):
                return contentType
            case .failure:
                return "application/json"
            }
        }
    }
}
