//
//  MenuBarInterface.swift
//  MenuBarInterface
//
//  Created by Anmol Jain on 11/25/23.
//

import AppKit

class MenuBarInterface: NSObject {
    
    public static func loadMenuItems(loadAsync: Bool, completion: @escaping (Result<[MenuItem], Error>) -> Void) {
        guard let app = NSWorkspace.shared.menuBarOwningApplication else {
            completion(.failure(NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unable to get application"])))
            return
        }
        
        let menuBar = MenuBar(for: app)
        switch menuBar.initState {
            case .success:
                break
                
            case .apiDisabled:
                completion(.failure(NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Accessibility API is disabled"])))
                return
                
            case .noValue:
                completion(.failure(NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unable to get menu bar"])))
                return
                
            default:
                completion(.failure(NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unknown error"])))
                return
        }
        
        let menuItems: [MenuItem]
        
        if loadAsync {
            menuItems = menuBar.loadAsync()
        } else {
            menuItems = menuBar.load()
        }
        
        completion(.success(menuItems))
    }
    
    @objc public static func clickMenuItem(clickIndices: [Int], completion: @escaping (Error?) -> Void) {
        guard let app = NSWorkspace.shared.menuBarOwningApplication else {
            completion(NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unable to get application"]))
            return
        }
        
        let menuBar = MenuBar(for: app)
        switch menuBar.initState {
            case .success:
                break
                
            case .apiDisabled:
                completion(NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Accessibility API is disabled"]))
                return
                
            case .noValue:
                completion(NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unable to get menu bar"]))
                return
                
            default:
                completion(NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unknown error"]))
                return
        }
        
        // Click the menu item
        menuBar.click(pathIndices: clickIndices)
        completion(nil)
    }
}
