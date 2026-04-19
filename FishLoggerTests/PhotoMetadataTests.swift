import Testing
import Foundation
import CoreLocation
@testable import FishLogger

struct PhotoMetadataTests {

    @Test
    func iso6709ParsesLatLon() {
        let c = PhotoMetadataExtractor.parseISO6709("+40.7128-074.0060+010.000/")
        #expect(c != nil)
        #expect(abs(c!.latitude - 40.7128) < 0.0001)
        #expect(abs(c!.longitude - -74.0060) < 0.0001)
    }

    @Test
    func iso6709ParsesSouthernWesternHemisphere() {
        let c = PhotoMetadataExtractor.parseISO6709("-33.8688-151.2093/")
        #expect(c != nil)
        #expect(c!.latitude < 0)
        #expect(c!.longitude < 0)
    }

    @Test
    func iso6709RejectsZeroZero() {
        let c = PhotoMetadataExtractor.parseISO6709("+00.0000+000.0000/")
        #expect(c == nil)
    }

    @Test
    func iso6709RejectsTooFewNumbers() {
        let c = PhotoMetadataExtractor.parseISO6709("nonsense")
        #expect(c == nil)
    }
}
