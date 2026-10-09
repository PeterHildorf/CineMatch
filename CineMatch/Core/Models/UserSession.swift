//
//  UserSession.swift
//  CineMatch
//
//  Created by Peter Hannibal Hildorf on 01/10/2026.
//


// name og email er optional, fordi apple gemmer det kun 1 gang
struct UserSession: Codable, Hashable, Sendable {
    let userID: String      // Supabase user id – nøglen til al brugerens data (og ML-servicen)
    let displayName: String?
    let email: String?
}
