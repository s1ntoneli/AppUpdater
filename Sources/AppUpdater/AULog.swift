//
//  File.swift
//  
//
//  Created by lixindong on 2024/8/9.
//

import Foundation
import OSLog

public class AULog {
    static let logger = Logger(subsystem: "com.gokoding.appupdater", category: "main")
    
    #if DEBUG
    public static var printLog = true
    #else
    public static var printLog = false
    #endif
    
    @inline(__always)
    static func log(_ messages: Any..., file: String = #file, function: String = #function) {
        let message = messages.reduce("") { "\($0) \($1)" }
        if Self.printLog {
            let fileName = URL(fileURLWithPath: file).lastPathComponent.split(separator: ".")[0]
            logger.log("\(fileName).\(function): \(message)")
        }
    }
}

@inline(__always)
public func aulog(_ messages: Any..., file: String = #file, function: String = #function) {
    AULog.log(messages, file: file, function: function)
}
