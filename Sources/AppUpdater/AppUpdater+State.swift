//
//  File.swift
//  
//
//  Created by lixindong on 2024/7/24.
//

import Foundation

public extension AppUpdater {

    enum UpdateState {
        /// no updates
        case none
        
        /// new version
        case newVersionDetected(Release, Release.Asset)
        
        /// the new version was downloading
        case downloading(Release, Release.Asset, fraction: Double)
        
        /// the bundle is ready
        case downloaded(Release, Release.Asset, Bundle)
        
        public var release: Release? {
            switch self {
            case .none:
                return nil
            case .newVersionDetected(let release, _):
                return release
            case .downloading(let release, _, _):
                return release
            case .downloaded(let release, _, _):
                return release
            }
        }
        
        public var asset: Release.Asset? {
            switch self {
            case .none:
                return nil
            case .newVersionDetected(_, let asset):
                return asset
            case .downloading(_, let asset, _):
                return asset
            case .downloaded(_, let asset, _):
                return asset
            }
        }
    }
}
