//
//  Formatters.swift
//  PodcastAnalyzer
//
//  Shared formatting utilities for playback speed and time display.
//

import Foundation

nonisolated enum Formatters {
  /// Selectable playback speed stops, shared by every speed picker/menu in the app.
  static let playbackSpeeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

  /// Format a playback speed value for display (e.g., 1.0 → "1x", 1.5 → "1.5x", 2.0 → "2x")
  static func formatSpeed(_ speed: Float) -> String {
    if speed == 1.0 {
      return "1x"
    } else if speed.truncatingRemainder(dividingBy: 1) == 0 {
      return "\(Int(speed))x"
    } else {
      return String(format: "%.2gx", speed)
    }
  }

  /// Format a time interval for playback display (e.g., 90 → "1:30", 3661 → "1:01:01")
  static func formatPlaybackTime(_ time: TimeInterval) -> String {
    guard time.isFinite && time >= 0 else { return "0:00" }

    let hours = Int(time) / 3600
    let minutes = Int(time) / 60 % 60
    let seconds = Int(time) % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
      return String(format: "%d:%02d", minutes, seconds)
    }
  }

  /// Format a relative date using compact units. Chinese locales use native
  /// suffixes like "1天前" and "2小時前" instead of English abbreviations.
  static func formatRelativeDate(_ date: Date, relativeTo referenceDate: Date = Date()) -> String {
    let locale = Locale.current
    let languageCode = locale.language.languageCode?.identifier ?? "en"
    let localeIdentifier = locale.identifier.lowercased()

    if languageCode.hasPrefix("zh") {
      let calendar = Calendar.current
      let components = calendar.dateComponents([.year, .month, .weekOfMonth, .day, .hour, .minute], from: date, to: referenceDate)
      let isSimplifiedChinese = localeIdentifier.contains("hans")

      let monthUnit = isSimplifiedChinese ? "个月前" : "個月前"
      let weekUnit = isSimplifiedChinese ? "周前" : "週前"
      let hourUnit = isSimplifiedChinese ? "小时前" : "小時前"
      let minuteUnit = isSimplifiedChinese ? "分钟前" : "分鐘前"
      let justNow = isSimplifiedChinese ? "刚刚" : "剛剛"

      if let year = components.year, abs(year) > 0 {
        return "\(abs(year))年前"
      }
      if let month = components.month, abs(month) > 0 {
        return "\(abs(month))\(monthUnit)"
      }
      if let week = components.weekOfMonth, abs(week) > 0 {
        return "\(abs(week))\(weekUnit)"
      }
      if let day = components.day, abs(day) > 0 {
        return "\(abs(day))天前"
      }
      if let hour = components.hour, abs(hour) > 0 {
        return "\(abs(hour))\(hourUnit)"
      }
      if let minute = components.minute, abs(minute) > 0 {
        return "\(abs(minute))\(minuteUnit)"
      }
      return justNow
    }

    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    formatter.locale = locale
    return formatter.localizedString(for: date, relativeTo: referenceDate)
  }
}
