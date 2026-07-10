import Testing
@testable import ObserverApp

struct PrivacyRedactorTests {
    @Test func redactsCommonSecrets() {
        let text = "password: hunter2 api_key=abcdefghijklmnopqrstuvwxyzABCDEFGHIJKL code 123456"
        let redacted = PrivacyRedactor.redact(text)

        #expect(!redacted.contains("hunter2"))
        #expect(!redacted.contains("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKL"))
        #expect(redacted.contains("[secret:credential]"))
    }

    @Test func redactsCardLikeNumbers() {
        let redacted = PrivacyRedactor.redact("card 4242 4242 4242 4242")
        #expect(redacted.contains("[secret:card_pan]"))
    }

    @Test func redacts2FACodesWithContext() {
        let redacted = PrivacyRedactor.redact("Your verification code is 123456")
        #expect(redacted.contains("[secret:2fa_code]"))
        #expect(!redacted.contains("123456"))
    }

    @Test func redactsIBANs() {
        let redacted = PrivacyRedactor.redact("IBAN GB82WEST12345698765432")
        #expect(redacted.contains("[secret:iban]"))
    }

    @Test func redactsSeedPhrases() {
        let phrase = "abandon ability able about above absent absorb abstract absurd abuse access accident"
        let redacted = PrivacyRedactor.redact(phrase)
        #expect(redacted == "[secret:seed_phrase]")
    }

    @Test func redactsPrivateKeys() {
        let redacted = PrivacyRedactor.redact("""
        -----BEGIN PRIVATE KEY-----
        abcdef
        -----END PRIVATE KEY-----
        """)
        #expect(redacted.contains("[secret:private_key]"))
    }
}
