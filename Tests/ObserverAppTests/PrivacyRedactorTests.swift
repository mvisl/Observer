import Testing
@testable import ObserverApp

struct PrivacyRedactorTests {
    @Test func redactsCommonSecrets() {
        let text = "password: hunter2 api_key=abcdefghijklmnopqrstuvwxyzABCDEFGHIJKL code 123456"
        let redacted = PrivacyRedactor.redact(text)

        #expect(!redacted.contains("hunter2"))
        #expect(!redacted.contains("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKL"))
        #expect(!redacted.contains("123456"))
        #expect(redacted.contains("[redacted]"))
    }

    @Test func redactsCardLikeNumbers() {
        let redacted = PrivacyRedactor.redact("card 4242 4242 4242 4242")
        #expect(redacted.contains("[redacted-card-like-number]"))
    }
}
