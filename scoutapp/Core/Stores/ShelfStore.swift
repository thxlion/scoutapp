//
//  ShelfStore.swift
//  scoutapp
//
//  Created by Codex on 05/11/2025.
//

import Foundation
import Observation

@Observable
final class ShelfStore {
  private let storageKey = "shelf.entries";
  private var entries: Set<String>;

  init() {
    if let saved = UserDefaults.standard.array(forKey: storageKey) as? [String] {
      entries = Set(saved);
    } else {
      entries = [];
    }
  }

  func contains(_ candidate: Candidate) -> Bool {
    entries.contains(candidate.identifier);
  }

  func toggle(_ candidate: Candidate) {
    if entries.contains(candidate.identifier) {
      entries.remove(candidate.identifier);
    } else {
      entries.insert(candidate.identifier);
    }
    persist();
  }

  private func persist() {
    UserDefaults.standard.set(Array(entries), forKey: storageKey);
  }
}
