//
//  Credits.swift
//  Blankie
//
//  Created by Cody Bromley on 5/30/25.
//

import Foundation

struct Credits: Codable {
  let contributors: [String]
  let translators: [String: [String]]
  let dependencies: [Dependency]?
}

struct Dependency: Codable {
  let name: String
  let author: String
  let license: String
  let url: String
}
