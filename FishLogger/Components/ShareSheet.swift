import SwiftUI
import UIKit

/// Thin wrapper around `UIActivityViewController` so a generated file URL can
/// be presented via `.sheet(item:)` (AirDrop, Files, Mail, etc.).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Identifiable URL wrapper for use as a `.sheet(item:)` payload.
struct ShareableFile: Identifiable {
    let id = UUID()
    let url: URL
}
