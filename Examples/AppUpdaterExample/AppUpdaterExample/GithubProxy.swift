//
//  File.swift
//  
//
//  Created by lixindong on 2024/7/22.
//

import Foundation
import AppUpdater

class GithubProxy: URLRequestProxy {
    let proxyUrl = "https://github-api-proxy.xxx.com?url="
    
    override func apply(to urlString: String) -> String {
        return "\(proxyUrl)\(urlString)"
    }
}
