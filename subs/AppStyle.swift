//
//  AppStyle.swift
//  subs
//

import SwiftUI

// MARK: - Styling

enum AppFormat {
    // The interface is English regardless of the system language; keep the user's region for date order.
    static let locale = Locale(languageCode: .english, languageRegion: Locale.current.region)
    static let shortDate = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(locale)
    static let longDate = Date.FormatStyle.dateTime.day().month(.wide).year().locale(locale)
}

enum AppColors {
    static let accent = Color(red: 0.40, green: 0.66, blue: 1)
    static let elapsed = Color(red: 0.96, green: 0.70, blue: 0.18)
    static let warning = Color(red: 1.00, green: 0.45, blue: 0.35)
}
