//
//  KeychainHandler.swift
//  TwinMindAssignment
//
//  Created by Noor Bhatia on 11/07/25.
//

import Foundation
import Security

class KeychainHandler {
    static let shared = KeychainHandler()

    private init() {}

    // Save data to Keychain
    func set(_ value: String, forKey key: Keys) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete any existing item
        _ = delete(key)

        let query: [String: Any] = [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrAccount as String : key.rawValue,
            kSecValueData as String   : data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // Retrieve data from Keychain
    func get(_ key: Keys) -> String? {
        let query: [String: Any] = [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrAccount as String : key.rawValue,
            kSecReturnData as String  : true,
            kSecMatchLimit as String  : kSecMatchLimitOne
        ]

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return value
    }

    // Delete data from Keychain
    func delete(_ key: Keys) -> Bool {
        let query: [String: Any] = [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrAccount as String : key.rawValue
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess
    }
    
    enum Keys:String{
        case kOpenAIKey = "kOpenAIKey"
    }
}
