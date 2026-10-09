//
//  KeychainHelper.swift
//  CineMatch
//
//  Created by Peter Hannibal Hildorf on 01/10/2026.
//

import Foundation
import Security

/// Beskriver hvad en Keychain kan. Protokollen gør det muligt at lave en mock i tests.
protocol KeychainStoring: Sendable {
    func save(_ value: String, for key: String) throws
    func read(key: String) throws -> String?
    func delete(key: String) throws
}

/// Keychain svarer med en statuskode (OSStatus) i stedet for at kaste fejl.
/// Vi pakker koden ind i en Swift-fejl, så vi kan bruge `throw`.
enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
    case invalidData
}

/// Den rigtige implementering, som gemmer værdier i iOS' Keychain.
struct KeychainHelper: KeychainStoring {
    /// Nøglen som Apple-bruger-ID'et gemmes under.
    static let appleUserIDKey = "appleUserID"

    /// Fungerer som en "mappe" for appens værdier i Keychain.
    private let service = "CineMatch"

    // MARK: - Gem

    func save(_ value: String, for key: String) throws {
        // Keychain gemmer rå bytes (Data), ikke tekst.
        let data = Data(value.utf8)

        // Slet en eventuel gammel værdi først, ellers fejler SecItemAdd med errSecDuplicateItem.
        SecItemDelete(baseQuery(for: key) as CFDictionary)

        var query = baseQuery(for: key)
        query[kSecValueData as String] = data
        // Værdien kan læses, når telefonen har været låst op én gang efter genstart.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Læs

    func read(key: String) throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true            // "giv mig dataen tilbage"
        query[kSecMatchLimit as String] = kSecMatchLimitOne // kun ét resultat

        // Keychain skriver resultatet ind i denne variabel (deraf `&`).
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidData
            }
            return value
        case errSecItemNotFound:
            // Ikke en fejl: der er bare ikke gemt noget endnu (fx ingen bruger logget ind).
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Slet

    func delete(key: String) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)

        // Hvis der ikke var noget at slette, er målet stadig nået.
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Hjælper

    /// Den fælles beskrivelse af "hvilket element" vi taler om. Bruges af alle tre funktioner.
    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword, // typen af element
            kSecAttrService as String: service,            // appens "mappe"
            kSecAttrAccount as String: key                 // navnet på værdien
        ]
    }
}
