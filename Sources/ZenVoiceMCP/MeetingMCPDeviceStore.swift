// Copyright 2026 Yash Chaudhary
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import Security

public struct MeetingMCPDeviceRecord: Codable, Equatable, Sendable {
    public var id: String
    public var secret: String
    public var pairing: String

    public init(id: String, secret: String, pairing: String) {
        self.id = id
        self.secret = secret
        self.pairing = pairing
    }
}

public enum MeetingMCPDeviceError: LocalizedError, Equatable {
    case keychain(OSStatus)
    case invalidRecord
    case missingOrigin
    case http(Int)
    case api(String)

    public var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return "Keychain error \(status)."
        case .invalidRecord:
            return "The stored MCP device record could not be read."
        case .missingOrigin:
            return "AI connectors have no relay origin."
        case .http(let status):
            return "MCP relay HTTP \(status)."
        case .api(let message):
            return message
        }
    }
}

public protocol MeetingMCPDeviceStoring: Sendable {
    func load() throws -> MeetingMCPDeviceRecord?
    func save(_ record: MeetingMCPDeviceRecord) throws
    func delete() throws
}

public struct MeetingMCPKeychainStore: MeetingMCPDeviceStoring, Sendable {
    private let service: String
    private let account: String

    public init(service: String, account: String = "mcp-device") {
        self.service = service
        self.account = account
    }

    public func load() throws -> MeetingMCPDeviceRecord? {
        let query = baseQuery.merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]) { _, new in new } as CFDictionary
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw MeetingMCPDeviceError.keychain(status)
        }
        guard let data = item as? Data else {
            throw MeetingMCPDeviceError.invalidRecord
        }
        return try JSONDecoder().decode(MeetingMCPDeviceRecord.self, from: data)
    }

    public func save(_ record: MeetingMCPDeviceRecord) throws {
        let data = try JSONEncoder().encode(record)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw MeetingMCPDeviceError.keychain(updateStatus)
        }
        let addQuery = baseQuery.merging([
            kSecValueData as String: data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]) { _, new in new } as CFDictionary
        let addStatus = SecItemAdd(addQuery, nil)
        guard addStatus == errSecSuccess else {
            throw MeetingMCPDeviceError.keychain(addStatus)
        }
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MeetingMCPDeviceError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

public final class InMemoryMeetingMCPDeviceStore: MeetingMCPDeviceStoring, @unchecked Sendable {
    private var record: MeetingMCPDeviceRecord?

    public init() {}

    public func load() throws -> MeetingMCPDeviceRecord? { record }

    public func save(_ record: MeetingMCPDeviceRecord) throws {
        self.record = record
    }

    public func delete() throws { record = nil }
}
