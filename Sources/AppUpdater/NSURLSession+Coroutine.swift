//
//  NSURLSession+Coroutine.swift
//  SecureYourClipboard
//
//  Created by lixindong on 2024/4/26.
//

import Foundation

extension URLSession {
    typealias TaskResult = (data: Data?, response: URLResponse?)
    
    func dataTask(with convertible: URLRequestConvertible, proxy: URLRequestProxy? = nil) async throws -> URLTaskResult? {
        aulog("dataTask", convertible, convertible.request.applyOrOriginal(proxy: proxy))
        
        return try await withCheckedThrowingContinuation { continuation in
            dataTask(with: convertible.request.applyOrOriginal(proxy: proxy)) { data, response, err in
                guard let data, let response else {
                    continuation.resume(throwing: err ?? AUError.invalidCallingConvention)
                    return
                }
                continuation.resume(returning: URLTaskResult(data: data, response: response))
            }.resume()
        }
    }
    
    func downloadTask(with convertible: URLRequestConvertible, to saveLocation: URL, proxy: URLRequestProxy? = nil) async throws -> AsyncThrowingStream<DownloadingState, Error> {
        aulog("downloadTask", convertible, convertible.request.applyOrOriginal(proxy: proxy))

        return AsyncThrowingStream<DownloadingState, Error> { continuation in
            Task(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                
                let task = downloadTask(with: convertible.request.applyOrOriginal(proxy: proxy)) { tmp, rso, err in
                    if let error = err {
                        continuation.finish(throwing: error)
                    } else if let rsp = rso, let tmp = tmp {
                        do {
                            try FileManager.default.moveItem(at: tmp, to: saveLocation)
                            continuation.yield(.finished(saveLocation: saveLocation, response: rsp))
                            continuation.finish()
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    } else {
                        continuation.finish(throwing: AUError.invalidCallingConvention)
                    }
                }
                continuation.yield(.progress(task.progress))
                task.resume()
            }
        }
   }
}

public struct URLTaskResult {
    let data: Data
    let response: URLResponse
}

public protocol URLRequestConvertible {
    var request: URLRequest { get }
}
extension URLRequest: URLRequestConvertible {
    public var request: URLRequest { return self }
}
extension URL: URLRequestConvertible {
    public var request: URLRequest { return URLRequest(url: self) }
}
extension String: URLRequestConvertible {
    public var request: URLRequest { return URLRequest(url: URL(string: self)!) }
}

extension URLTaskResult {
    func validate() throws -> URLTaskResult {
        guard let response = self.response as? HTTPURLResponse else { return self }
        switch response.statusCode {
        case 200..<300:
            return self
        case let code:
            throw CRTHTTPError.badStatusCode(code, self.data, response)
        }
    }
}

#if swift(>=3.1)
public enum CRTHTTPError: Error, LocalizedError, CustomStringConvertible {
    case badStatusCode(Int, Data, HTTPURLResponse)

    public var errorDescription: String? {
        func url(_ rsp: URLResponse) -> String {
            return rsp.url?.absoluteString ?? "nil"
        }
        switch self {
        case .badStatusCode(401, _, let response):
            return "Unauthorized (\(url(response))"
        case .badStatusCode(let code, _, let response):
            return "Invalid HTTP response (\(code)) for \(url(response))."
        }
    }

#if swift(>=4.0)
    public func decodeResponse<T: Decodable>(_ t: T.Type, decoder: JSONDecoder = JSONDecoder()) -> T? {
        switch self {
        case .badStatusCode(_, let data, _):
            return try? decoder.decode(t, from: data)
        }
    }
#endif

    //TODO rename responseJSON
    public var jsonDictionary: Any? {
        switch self {
        case .badStatusCode(_, let data, _):
            return try? JSONSerialization.jsonObject(with: data)
        }
    }

    var responseBodyString: String? {
        switch self {
        case .badStatusCode(_, let data, _):
            return String(data: data, encoding: .utf8)
        }
    }

    public var failureReason: String? {
        return responseBodyString
    }

    public var description: String {
        switch self {
        case .badStatusCode(let code, let data, let response):
            var dict: [String: Any] = [
                "Status Code": code,
                "Body": String(data: data, encoding: .utf8) ?? "\(data.count) bytes"
            ]
            dict["URL"] = response.url
            dict["Headers"] = response.allHeaderFields
            return "<NSHTTPResponse> \(NSDictionary(dictionary: dict))" // as NSDictionary makes the output look like NSHTTPURLResponse looks
        }
    }
}
#endif

enum DownloadingState {
    case progress(Progress)
    case finished(saveLocation: URL, response: URLResponse)
}
