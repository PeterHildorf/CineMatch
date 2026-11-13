//
//  UserSession.swift
//  CineMatch
//
//  Created by Peter Hannibal Hildorf on 01/10/2026.
//


struct UserSession: Codable, Hashable, Sendable {
    let userID: String      // Supabase user id – nøglen til al brugerens data (og ML-servicen)
    let email: String?
}
