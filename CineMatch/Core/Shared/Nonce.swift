//
//  Nonce.swift
//  CineMatch
//

import CryptoKit
import Foundation
import Security

/// En nonce er en tilfældig engangs-streng, som beskytter mod "replay"-angreb:
/// Apple lægger den hashede nonce ind i sit token, og Supabase tjekker,
/// at hashen af den rå nonce, vi sender, passer med den i tokenet.
enum Nonce {
    /// Laver en kryptografisk tilfældig streng.
    static func random(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        precondition(status == errSecSuccess, "Kunne ikke lave tilfældige bytes")
        // Hver tilfældig byte vælger et tegn fra charset.
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    /// SHA256-hash som hex-tekst. Det er denne version, Apple skal have.
    static func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
