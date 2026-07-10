import Testing
@testable import ObserverApp

struct AudioOutputServiceTests {
    @Test func recognizesHeadphoneLikeOutputs() {
        let service = AudioOutputService()

        #expect(service.looksLikeHeadphones("AirPods Pro"))
        #expect(service.looksLikeHeadphones("WH-1000XM5"))
        #expect(!service.looksLikeHeadphones("MacBook Pro Speakers"))
    }
}
