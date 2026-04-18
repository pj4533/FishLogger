import Foundation
import SwiftData

@Model
final class Species {
    @Attribute(.unique) var commonName: String
    var scientificName: String
    var speciesDescription: String
    var sortOrder: Int

    @Relationship(inverse: \Catch.species)
    var catches: [Catch] = []

    init(commonName: String, scientificName: String, speciesDescription: String = "", sortOrder: Int = 0) {
        self.commonName = commonName
        self.scientificName = scientificName
        self.speciesDescription = speciesDescription
        self.sortOrder = sortOrder
    }
}
