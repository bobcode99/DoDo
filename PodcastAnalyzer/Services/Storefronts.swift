//
//  Storefronts.swift
//  PodcastAnalyzer
//
//  GENERATED FILE — do not hand-edit.
//
//  The set of Apple Podcasts storefronts, verified against
//  rss.marketingtools.apple.com by probing every ISO 3166-1 alpha-2 code: a live
//  storefront answers 200, a nonexistent one answers 500. Regenerating is a
//  scripted step, never something the app does — nothing here touches the
//  network at runtime.
//
//  Verified 2026-08-22. 174 of 249 codes are live storefronts.
//  See locales.md for the same list in readable form.
//

import Foundation

/// One Apple Podcasts storefront.
struct Storefront: Identifiable, Hashable, Sendable {
  /// Lowercased ISO 3166-1 alpha-2 code, as the API path expects it.
  let code: String
  /// English display name, from CLDR via Foundation.
  let name: String

  var id: String { code }

  /// Regional-indicator flag derived from the code, so no emoji is stored.
  var flag: String {
    String(String.UnicodeScalarView(code.unicodeScalars.compactMap {
      Unicode.Scalar(0x1F1E6 + $0.value - UInt32(UnicodeScalar("a").value))
    }))
  }
}

extension Storefront {
  /// Every verified storefront, ordered by English name.
  static let all: [Storefront] = [
    Storefront(code: "af", name: "Afghanistan"),
    Storefront(code: "al", name: "Albania"),
    Storefront(code: "dz", name: "Algeria"),
    Storefront(code: "ao", name: "Angola"),
    Storefront(code: "ai", name: "Anguilla"),
    Storefront(code: "ag", name: "Antigua & Barbuda"),
    Storefront(code: "ar", name: "Argentina"),
    Storefront(code: "am", name: "Armenia"),
    Storefront(code: "au", name: "Australia"),
    Storefront(code: "at", name: "Austria"),
    Storefront(code: "az", name: "Azerbaijan"),
    Storefront(code: "bs", name: "Bahamas"),
    Storefront(code: "bh", name: "Bahrain"),
    Storefront(code: "bb", name: "Barbados"),
    Storefront(code: "by", name: "Belarus"),
    Storefront(code: "be", name: "Belgium"),
    Storefront(code: "bz", name: "Belize"),
    Storefront(code: "bj", name: "Benin"),
    Storefront(code: "bm", name: "Bermuda"),
    Storefront(code: "bt", name: "Bhutan"),
    Storefront(code: "bo", name: "Bolivia"),
    Storefront(code: "ba", name: "Bosnia & Herzegovina"),
    Storefront(code: "bw", name: "Botswana"),
    Storefront(code: "br", name: "Brazil"),
    Storefront(code: "vg", name: "British Virgin Islands"),
    Storefront(code: "bn", name: "Brunei"),
    Storefront(code: "bg", name: "Bulgaria"),
    Storefront(code: "bf", name: "Burkina Faso"),
    Storefront(code: "kh", name: "Cambodia"),
    Storefront(code: "cm", name: "Cameroon"),
    Storefront(code: "ca", name: "Canada"),
    Storefront(code: "cv", name: "Cape Verde"),
    Storefront(code: "ky", name: "Cayman Islands"),
    Storefront(code: "td", name: "Chad"),
    Storefront(code: "cl", name: "Chile"),
    Storefront(code: "cn", name: "China mainland"),
    Storefront(code: "co", name: "Colombia"),
    Storefront(code: "cg", name: "Congo - Brazzaville"),
    Storefront(code: "cd", name: "Congo - Kinshasa"),
    Storefront(code: "cr", name: "Costa Rica"),
    Storefront(code: "hr", name: "Croatia"),
    Storefront(code: "cy", name: "Cyprus"),
    Storefront(code: "cz", name: "Czechia"),
    Storefront(code: "ci", name: "Côte d’Ivoire"),
    Storefront(code: "dk", name: "Denmark"),
    Storefront(code: "dm", name: "Dominica"),
    Storefront(code: "do", name: "Dominican Republic"),
    Storefront(code: "ec", name: "Ecuador"),
    Storefront(code: "eg", name: "Egypt"),
    Storefront(code: "sv", name: "El Salvador"),
    Storefront(code: "ee", name: "Estonia"),
    Storefront(code: "sz", name: "Eswatini"),
    Storefront(code: "fj", name: "Fiji"),
    Storefront(code: "fi", name: "Finland"),
    Storefront(code: "fr", name: "France"),
    Storefront(code: "ga", name: "Gabon"),
    Storefront(code: "gm", name: "Gambia"),
    Storefront(code: "ge", name: "Georgia"),
    Storefront(code: "de", name: "Germany"),
    Storefront(code: "gh", name: "Ghana"),
    Storefront(code: "gr", name: "Greece"),
    Storefront(code: "gd", name: "Grenada"),
    Storefront(code: "gt", name: "Guatemala"),
    Storefront(code: "gw", name: "Guinea-Bissau"),
    Storefront(code: "gy", name: "Guyana"),
    Storefront(code: "hn", name: "Honduras"),
    Storefront(code: "hk", name: "Hong Kong"),
    Storefront(code: "hu", name: "Hungary"),
    Storefront(code: "is", name: "Iceland"),
    Storefront(code: "in", name: "India"),
    Storefront(code: "id", name: "Indonesia"),
    Storefront(code: "iq", name: "Iraq"),
    Storefront(code: "ie", name: "Ireland"),
    Storefront(code: "il", name: "Israel"),
    Storefront(code: "it", name: "Italy"),
    Storefront(code: "jm", name: "Jamaica"),
    Storefront(code: "jp", name: "Japan"),
    Storefront(code: "jo", name: "Jordan"),
    Storefront(code: "kz", name: "Kazakhstan"),
    Storefront(code: "ke", name: "Kenya"),
    Storefront(code: "kw", name: "Kuwait"),
    Storefront(code: "kg", name: "Kyrgyzstan"),
    Storefront(code: "la", name: "Laos"),
    Storefront(code: "lv", name: "Latvia"),
    Storefront(code: "lb", name: "Lebanon"),
    Storefront(code: "lr", name: "Liberia"),
    Storefront(code: "ly", name: "Libya"),
    Storefront(code: "lt", name: "Lithuania"),
    Storefront(code: "lu", name: "Luxembourg"),
    Storefront(code: "mo", name: "Macao"),
    Storefront(code: "mg", name: "Madagascar"),
    Storefront(code: "mw", name: "Malawi"),
    Storefront(code: "my", name: "Malaysia"),
    Storefront(code: "mv", name: "Maldives"),
    Storefront(code: "ml", name: "Mali"),
    Storefront(code: "mt", name: "Malta"),
    Storefront(code: "mr", name: "Mauritania"),
    Storefront(code: "mu", name: "Mauritius"),
    Storefront(code: "mx", name: "Mexico"),
    Storefront(code: "fm", name: "Micronesia"),
    Storefront(code: "md", name: "Moldova"),
    Storefront(code: "mn", name: "Mongolia"),
    Storefront(code: "me", name: "Montenegro"),
    Storefront(code: "ms", name: "Montserrat"),
    Storefront(code: "ma", name: "Morocco"),
    Storefront(code: "mz", name: "Mozambique"),
    Storefront(code: "mm", name: "Myanmar (Burma)"),
    Storefront(code: "na", name: "Namibia"),
    Storefront(code: "nr", name: "Nauru"),
    Storefront(code: "np", name: "Nepal"),
    Storefront(code: "nl", name: "Netherlands"),
    Storefront(code: "nz", name: "New Zealand"),
    Storefront(code: "ni", name: "Nicaragua"),
    Storefront(code: "ne", name: "Niger"),
    Storefront(code: "ng", name: "Nigeria"),
    Storefront(code: "mk", name: "North Macedonia"),
    Storefront(code: "no", name: "Norway"),
    Storefront(code: "om", name: "Oman"),
    Storefront(code: "pk", name: "Pakistan"),
    Storefront(code: "pw", name: "Palau"),
    Storefront(code: "pa", name: "Panama"),
    Storefront(code: "pg", name: "Papua New Guinea"),
    Storefront(code: "py", name: "Paraguay"),
    Storefront(code: "pe", name: "Peru"),
    Storefront(code: "ph", name: "Philippines"),
    Storefront(code: "pl", name: "Poland"),
    Storefront(code: "pt", name: "Portugal"),
    Storefront(code: "qa", name: "Qatar"),
    Storefront(code: "ro", name: "Romania"),
    Storefront(code: "ru", name: "Russia"),
    Storefront(code: "rw", name: "Rwanda"),
    Storefront(code: "sa", name: "Saudi Arabia"),
    Storefront(code: "sn", name: "Senegal"),
    Storefront(code: "rs", name: "Serbia"),
    Storefront(code: "sc", name: "Seychelles"),
    Storefront(code: "sl", name: "Sierra Leone"),
    Storefront(code: "sg", name: "Singapore"),
    Storefront(code: "sk", name: "Slovakia"),
    Storefront(code: "si", name: "Slovenia"),
    Storefront(code: "sb", name: "Solomon Islands"),
    Storefront(code: "za", name: "South Africa"),
    Storefront(code: "kr", name: "South Korea"),
    Storefront(code: "es", name: "Spain"),
    Storefront(code: "lk", name: "Sri Lanka"),
    Storefront(code: "kn", name: "St. Kitts & Nevis"),
    Storefront(code: "lc", name: "St. Lucia"),
    Storefront(code: "vc", name: "St. Vincent & Grenadines"),
    Storefront(code: "sr", name: "Suriname"),
    Storefront(code: "se", name: "Sweden"),
    Storefront(code: "ch", name: "Switzerland"),
    Storefront(code: "st", name: "São Tomé & Príncipe"),
    Storefront(code: "tw", name: "Taiwan"),
    Storefront(code: "tj", name: "Tajikistan"),
    Storefront(code: "tz", name: "Tanzania"),
    Storefront(code: "th", name: "Thailand"),
    Storefront(code: "to", name: "Tonga"),
    Storefront(code: "tt", name: "Trinidad & Tobago"),
    Storefront(code: "tn", name: "Tunisia"),
    Storefront(code: "tm", name: "Turkmenistan"),
    Storefront(code: "tc", name: "Turks & Caicos Islands"),
    Storefront(code: "tr", name: "Türkiye"),
    Storefront(code: "ug", name: "Uganda"),
    Storefront(code: "ua", name: "Ukraine"),
    Storefront(code: "ae", name: "United Arab Emirates"),
    Storefront(code: "gb", name: "United Kingdom"),
    Storefront(code: "us", name: "United States"),
    Storefront(code: "uy", name: "Uruguay"),
    Storefront(code: "uz", name: "Uzbekistan"),
    Storefront(code: "vu", name: "Vanuatu"),
    Storefront(code: "ve", name: "Venezuela"),
    Storefront(code: "vn", name: "Vietnam"),
    Storefront(code: "ye", name: "Yemen"),
    Storefront(code: "zm", name: "Zambia"),
    Storefront(code: "zw", name: "Zimbabwe"),
  ]

  /// Lookup by code. Nil for anything not in the verified list — including a
  /// custom code the user added, which is why callers fall back to the raw code
  /// rather than treating nil as an error.
  static func named(_ code: String) -> Storefront? {
    byCode[code.lowercased()]
  }

  /// Code-keyed index, built once. `all` is 174 entries and `named` is called
  /// per row while a list scrolls, so a linear search here would be the wrong
  /// shape even though the constant is small.
  private static let byCode: [String: Storefront] =
    Dictionary(uniqueKeysWithValues: all.map { ($0.code, $0) })

  /// Whether a code is a known-good storefront. A custom code the user verified
  /// by probing will be absent, so this is a "did we ship it" test, not a
  /// validity test.
  static func isKnown(_ code: String) -> Bool {
    byCode[code.lowercased()] != nil
  }
}
