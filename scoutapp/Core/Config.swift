//
//  Config.swift
//  scoutapp
//
//  Created by Codex on 05/11/2025.
//

import Foundation

enum Config {
  static let workerBase = URL(string: "https://scout-worker.zvkarry.workers.dev")!;
  static let imgBase = URL(string: "https://image.tmdb.org/t/p/")!;
  static let posterSize = "w342";
  static let region = "GB";

  /// Convenience helper for building full poster URLs
  static func posterURL(path: String?) -> URL? {
    guard let path else { return nil; }
    let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path;
    return imgBase.appending(path: posterSize).appending(path: trimmed);
  }
}
