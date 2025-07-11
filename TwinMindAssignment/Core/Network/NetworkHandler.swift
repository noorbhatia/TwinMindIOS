//
//  NetworkHandler.swift
//  TwinMindAssignment
//
//  Created by Noor Bhatia on 11/07/25.
//

import Foundation

enum HTTPMethod: String {
    case GET, POST
}

struct Endpoint {
    let path: String
    let method: HTTPMethod
    let queryItems: [URLQueryItem]?
    
    func url(baseUrl: String) -> URL? {
        var components = URLComponents(string: baseUrl + path)
        components?.queryItems = queryItems
        return components?.url
    }
}

// MARK: - OpenAI API Configuration
struct APIConfig {
    let openaiAPIKey: String
    let openaiBaseURL: String
    let model: String
    let temperature: Double
    let language: String?
    
    static let `default` = APIConfig(
        openaiAPIKey: "", // To be configured
        openaiBaseURL: "https://api.openai.com/v1",
        model: "whisper-1",
        temperature: 0.0,
        language: nil // Auto-detect
    )
}

protocol NetworkHandlerProtocol {
    func fetch<T: Decodable>(_ endpoint: Endpoint, baseURL: String) async throws -> T
    func uploadMultipartFile<T: Decodable>(fileURL: URL, endpoint: Endpoint, config: APIConfig) async throws -> T
}

final class NetworkHandler: NetworkHandlerProtocol {
    
    static let shared = NetworkHandler()
    private init() {}
    
    func fetch<T: Decodable>(_ endpoint: Endpoint, baseURL: String) async throws -> T {
        guard let url = endpoint.url(baseUrl: baseURL) else {
            throw NSError(domain: "NetworkError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw NSError(domain: "NetworkError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Request failed"])
        }
        
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw NSError(domain: "NetworkError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Decoding failed: \(error.localizedDescription)"])
        }
    }
    
    func uploadMultipartFile<T: Decodable>(fileURL: URL, endpoint: Endpoint, config: APIConfig) async throws -> T {
        // Prepare multipart form data
        let boundary = "Boundary-\(UUID().uuidString)"
        let httpBody = try? createMultipartBody(
            fileURL: fileURL,
            boundary: boundary,
            config: config
        )
        
        guard let url = endpoint.url(baseUrl: config.openaiBaseURL) else {
            throw NSError(domain: "NetworkError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        guard let key = KeychainHandler.shared.get(.kOpenAIKey) else {
            throw NSError(domain: "NetworkError", code: 5, userInfo: [NSLocalizedDescriptionKey: "API key not configured"])
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody
        
        do {
            // Perform request
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Check response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "NetworkError", code: 6, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }
            
            guard 200...299 ~= httpResponse.statusCode else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw NSError(domain: "NetworkError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API error (\(httpResponse.statusCode)): \(errorMessage)"])
            }
            
            // Parse response
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            if let nsError = error as? NSError, nsError.domain == "NetworkError" {
                throw error // Re-throw our custom errors
            }
            throw NSError(domain: "NetworkError", code: 7, userInfo: [NSLocalizedDescriptionKey: "Unknown error: \(error.localizedDescription)"])
        }
    }
}

extension NetworkHandler {
    private func createMultipartBody(
        fileURL: URL,
        boundary: String,
        config: APIConfig
    ) throws -> Data {
        var body = Data()
        let audioData = try Data(contentsOf: fileURL)
        
        // Add file data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append(config.model.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add response format
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("verbose_json".data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        
        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        return body
    }
}
