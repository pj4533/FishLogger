import SwiftUI

extension Font {
    static let diaryTitle     = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let diaryHeader    = Font.system(.title2, design: .rounded, weight: .semibold)
    static let species        = Font.system(.title3, design: .rounded, weight: .semibold)
    static let scientificName = Font.system(.footnote, design: .serif).italic()
    static let fieldLabel     = Font.system(.caption, design: .rounded, weight: .medium).smallCaps()
    static let statValue      = Font.system(.title, design: .rounded, weight: .heavy)
    static let cozyBody       = Font.system(.body, design: .rounded)
    static let cozyCaption    = Font.system(.caption, design: .rounded)
}
