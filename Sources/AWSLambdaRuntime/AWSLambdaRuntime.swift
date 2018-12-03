import Foundation

public struct Runtime {
    public struct Context {
        let payload: Data?
        let requestID: String
        let functionARN: String
        let deadline: Date
        let xrayTraceID: String
        let clientContext: [String: Any]?
        let cognitoIdentifier: [String: Any]?
        var remainingTime: TimeInterval {
            return deadline.timeIntervalSinceNow
        }
    }
    
    public enum Error: Swift.Error {
        case UnexpectedError(message: String)
        case APIError(statusCode: Int)
    }
    
    public enum Result {
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
    
    private struct Endpoint {
        let apiVersion = "2018-06-01"
        let baseURL: URL
        
        init?(runtimeAPI: String) {
            guard let urlString = URL(string: "http://\(runtimeAPI)") else {
                return nil
            }
            baseURL = urlString
        }
        
        var initialize: URL {
            return baseURL.appendingPathComponent("/\(apiVersion)/runtime/init/error")
        }
        
        var next: URL {
            return baseURL.appendingPathComponent("/\(apiVersion)/runtime/invocation/next")
        }
        
        func response(requestID: String) -> URL {
            return baseURL.appendingPathComponent("/\(apiVersion)/runtime/invocation/\(requestID)/response/")
        }
        
        func error(requestID: String) -> URL {
            return baseURL.appendingPathComponent("/\(apiVersion)/runtime/invocation/\(requestID)/error/")
        }
    }
    
    public typealias Handler = (Context) -> Result
    public func run(_ handler: Handler) {
        guard let runtimeAPI = ProcessInfo.processInfo.environment["AWS_LAMBDA_RUNTIME_API"],
            let endpoint = Endpoint(runtimeAPI: runtimeAPI) else {
                fatalError("LAMBDA_SERVER_ADDRESS is not defined.")
        }
        
        let maxRetryCount = 3
        for _ in 0..<maxRetryCount {
            guard let context = try? fetchNextEvent(endpoint: endpoint) else {
                continue
            }
            let result = handler(context)
            do {
                try postResult(result, of: context, to: endpoint)
            } catch {
                continue
            }
        }
        
        fatalError("Exhausted all retries.")
    }
    
    private func postResult(_ result: Result, of context: Context, to endpoint: Endpoint) throws {
        var request: URLRequest
        switch result {
        case .success:
            request = URLRequest(url: endpoint.response(requestID: context.requestID))
        case .failure:
            request = URLRequest(url: endpoint.error(requestID: context.requestID))
        }
        
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = [
            "content-type": result.contentType,
            "Expect": "",
            "transfer-encoding": "",
            "content-length": String(result.payload.count),
            ]
        request.httpBody = result.payload
        
        var thrownError: Error? = nil
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let response = response as? HTTPURLResponse else {
                fatalError()
            }
            
            let isSuccess = (200...300).contains(response.statusCode)
            if !isSuccess {
                thrownError = Error.APIError(statusCode: response.statusCode)
                return
            }
        }.resume()
        
        if let error = thrownError { throw error }
    }
    
    private func fetchNextEvent(endpoint: Endpoint) throws -> Context {
        func createContext(data: Data?, response: HTTPURLResponse) throws -> Context {
            guard let requestID = response.allHeaderFields["Lambda-Runtime-Aws-Request-Id"] as? String else {
                throw Error.UnexpectedError(message: "Missing Lambda-Runtime-Aws-Request-Id Header")
            }
            guard let functionARN = response.allHeaderFields["Lambda-Runtime-Invoked-Function-Arn"] as? String else {
                throw Error.UnexpectedError(message: "Missing Lambda-Runtime-Invoked-Function-Arn Header")
            }
            guard let traceID = response.allHeaderFields["Lambda-Runtime-Trace-Id"] as? String else {
                throw Error.UnexpectedError(message: "Missing Lambda-Runtime-Trace-Id Header")
            }
            guard let deadlineString = response.allHeaderFields["Lambda-Runtime-Deadline-Ms"] as? String,
                let milisecond = Double(deadlineString) else {
                    throw Error.UnexpectedError(message: "Missing Lambda-Runtime-Deadline-Ms")
            }
            let deadline = Date(timeIntervalSince1970: milisecond / 1000)
            
            let clientContext: [String: Any]?
            if let clientContextJSON = response.allHeaderFields["Lambda-Runtime-Client-Context"] as? String {
                let data = clientContextJSON.data(using: .utf8)!
                clientContext = (try? JSONSerialization.jsonObject(with: data)) as? [String : Any]
            } else {
                clientContext = nil
            }
            
            let cognitoIdentifier: [String: Any]?
            if let cognitoIdentifierJSON = response.allHeaderFields["Lambda-Runtime-Cognito-Identity"] as? String {
                let data = cognitoIdentifierJSON.data(using: .utf8)!
                cognitoIdentifier = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            } else {
                cognitoIdentifier = nil
            }
            return Context(payload: data,
                           requestID: requestID,
                           functionARN: functionARN,
                           deadline: deadline,
                           xrayTraceID: traceID,
                           clientContext: clientContext,
                           cognitoIdentifier: cognitoIdentifier)
        }
        
        var context: Context!
        var thrownError: Error? = nil
        URLSession.shared.dataTask(with: endpoint.next) { data, response, error in
            do {
                guard let response = response as? HTTPURLResponse else {
                    fatalError()
                }
                context = try createContext(data: data, response: response)
            } catch {
                thrownError = error as? Runtime.Error
            }
            
        }.resume()
        
        if let error = thrownError { throw error }
        return context
    }
}
