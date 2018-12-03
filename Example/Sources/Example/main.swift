import Foundation
import AWSLambdaRuntime

struct User: Decodable {
    let firstName: String
}

enum GreetingError: String, LambdaError {
    var message: String {
        switch self {
        case .invalidPayload:
            return "Payload is invalid"
        }
    }
    
    case invalidPayload
}

run { context -> Result<GreetingError> in
    guard let data = context.payload,
        let user = try? JSONDecoder().decode(User.self, from: data) else {
        return .failure(error: .invalidPayload)
    }
    let payload = try! JSONSerialization.data(withJSONObject: ["message": "Hello \(user.firstName)"])
    return .success(payload: payload, contentType: "application/json")
}
