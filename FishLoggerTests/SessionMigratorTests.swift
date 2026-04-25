import Testing
import Foundation
import SwiftData
@testable import FishLogger

@MainActor
struct SessionMigratorTests {

    private func makeCatch(at seconds: Double, lat: Double = 41.5, lon: Double = -74.0) -> Catch {
        let c = Catch(
            timestamp: Date(timeIntervalSince1970: seconds),
            latitude: lat,
            longitude: lon
        )
        return c
    }

    @Test
    func emptyInputReturnsEmpty() {
        let groups = SessionMigrator.groupByTimeAndProximity(
            [],
            gapSeconds: 6 * 3600,
            radiusMeters: 100
        )
        #expect(groups.isEmpty)
    }

    @Test
    func catchesWithinGapStayInOneGroup() throws {
        // Four catches spaced 30 minutes apart at the same location — one session.
        let catches = [
            makeCatch(at: 0),
            makeCatch(at: 1800),
            makeCatch(at: 3600),
            makeCatch(at: 5400)
        ]
        let groups = SessionMigrator.groupByTimeAndProximity(
            catches,
            gapSeconds: 6 * 3600,
            radiusMeters: 100
        )
        #expect(groups.count == 1)
        #expect(groups[0].count == 4)
    }

    @Test
    func gapLargerThanThresholdSplitsGroups() throws {
        // Two catches 4 hours apart (same group), then 8 hours (new group).
        let catches = [
            makeCatch(at: 0),
            makeCatch(at: 4 * 3600),
            makeCatch(at: 12 * 3600), // 8h after previous → new session
            makeCatch(at: 13 * 3600)
        ]
        let groups = SessionMigrator.groupByTimeAndProximity(
            catches,
            gapSeconds: 6 * 3600,
            radiusMeters: 100
        )
        #expect(groups.count == 2)
        #expect(groups[0].count == 2)
        #expect(groups[1].count == 2)
    }

    @Test
    func crossMidnightStaysInOneGroup() throws {
        // Night fishing: 10pm and 1am the next day. 3-hour gap — should stay together.
        let cal = Calendar(identifier: .gregorian)
        var ref = DateComponents()
        ref.year = 2024; ref.month = 7; ref.day = 15
        ref.hour = 22; ref.minute = 0
        let tenPM = cal.date(from: ref)!
        let oneAM = tenPM.addingTimeInterval(3 * 3600)

        let catches = [
            Catch(timestamp: tenPM, latitude: 41.5, longitude: -74.0),
            Catch(timestamp: oneAM, latitude: 41.5, longitude: -74.0)
        ]
        let groups = SessionMigrator.groupByTimeAndProximity(
            catches,
            gapSeconds: 6 * 3600,
            radiusMeters: 100
        )
        #expect(groups.count == 1)
        #expect(groups[0].count == 2)
    }

    @Test
    func movingBeyondRadiusSplitsEvenWithSmallTimeGap() throws {
        // Two catches 10 minutes apart but 500m apart — different spots mid-day,
        // so we treat them as separate sessions.
        let a = makeCatch(at: 0, lat: 41.5, lon: -74.0)
        // ~500m north at the same time slot
        let b = makeCatch(at: 600, lat: 41.5045, lon: -74.0)

        let groups = SessionMigrator.groupByTimeAndProximity(
            [a, b],
            gapSeconds: 6 * 3600,
            radiusMeters: 100
        )
        #expect(groups.count == 2)
    }

    @Test
    func migrateIfNeededCreatesSessionsForOrphans() throws {
        let container = try TestContainer.make()
        let context = container.mainContext

        // Clear the "already ran" flag so the test isn't suppressed by another run.
        UserDefaults.standard.removeObject(forKey: "FishLogger.SessionMigrator.didRun.v1")

        // Two orphan catches in one session window.
        let c1 = Catch(
            timestamp: Date(timeIntervalSince1970: 0),
            latitude: 41.5, longitude: -74.0
        )
        let c2 = Catch(
            timestamp: Date(timeIntervalSince1970: 1800),
            latitude: 41.5, longitude: -74.0
        )
        context.insert(c1)
        context.insert(c2)
        try context.save()

        SessionMigrator.migrateIfNeeded(context: context)

        let sessions = try context.fetch(FetchDescriptor<Session>())
        #expect(sessions.count == 1)
        #expect(sessions[0].catches.count == 2)
        #expect(c1.session === sessions[0])
        #expect(c2.session === sessions[0])
        #expect(sessions[0].spot != nil)
    }
}
