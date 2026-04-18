import SwiftUI

struct FishIcon: View {
    let commonName: String
    var size: CGFloat = 28
    var wiggle: Bool = false

    private var symbolName: String {
        switch commonName.lowercased() {
        case let n where n.contains("bass"):        return "fish.fill"
        case let n where n.contains("pickerel"),
             let n where n.contains("pike"):        return "fish.fill"
        case let n where n.contains("perch"),
             let n where n.contains("crappie"),
             let n where n.contains("sunfish"),
             let n where n.contains("bluegill"),
             let n where n.contains("pumpkinseed"): return "fish.fill"
        case let n where n.contains("catfish"),
             let n where n.contains("bullhead"):    return "fish.fill"
        case let n where n.contains("carp"),
             let n where n.contains("shiner"):      return "fish.fill"
        default:                                     return "fish.fill"
        }
    }

    private var tint: Color {
        switch commonName.lowercased() {
        case let n where n.contains("bass"):        return .moss
        case let n where n.contains("pickerel"),
             let n where n.contains("pike"):        return .waterDeep
        case let n where n.contains("perch"):       return .sunset
        case let n where n.contains("crappie"):     return .ink
        case let n where n.contains("bluegill"),
             let n where n.contains("sunfish"),
             let n where n.contains("pumpkinseed"): return .sunset
        case let n where n.contains("catfish"),
             let n where n.contains("bullhead"):    return .bark
        case let n where n.contains("carp"):        return .bark
        case let n where n.contains("shiner"):      return .inkFaded
        default:                                     return .waterDeep
        }
    }

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(tint)
            .symbolRenderingMode(.hierarchical)
            .modifier(ConditionalWiggle(active: wiggle))
    }
}

private struct ConditionalWiggle: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active {
            content.symbolEffect(.wiggle, options: .repeat(.periodic(delay: 2.5)))
        } else {
            content
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        FishIcon(commonName: "Largemouth Bass", size: 40, wiggle: true)
        FishIcon(commonName: "Bluegill", size: 40)
        FishIcon(commonName: "Chain Pickerel", size: 40)
        FishIcon(commonName: "Brown Bullhead Catfish", size: 40)
    }
    .padding()
    .background(Color.paper)
}
