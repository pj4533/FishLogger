import Testing
import Foundation
import SwiftData
@testable import FishLogger

@MainActor
struct AssistantServiceTests {

    @Test
    func startWithoutKeySurfacesError() async throws {
        let container = try TestContainer.make()
        let context = container.mainContext
        _ = container
        let session = Session(latitude: 41.5, longitude: -73.9)
        context.insert(session)

        let service = AssistantService(keychain: MockKeychain(initial: nil))
        await service.start(session: session, context: context, species: [])

        #expect(service.phase == .error("Add your OpenAI API key in Settings to use the assistant."))
        #expect(!service.isActive)
    }
}
