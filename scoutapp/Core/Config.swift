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

    // If it's already a full URL (from OMDb), return it as-is
    if path.hasPrefix("http://") || path.hasPrefix("https://") {
      return URL(string: path);
    }

    // Otherwise, construct TMDB URL
    let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path;
    return imgBase.appending(path: posterSize).appending(path: trimmed);
  }
}
