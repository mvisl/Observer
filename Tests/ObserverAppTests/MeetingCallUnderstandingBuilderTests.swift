import Foundation
import Testing
@testable import ObserverApp

struct MeetingCallUnderstandingBuilderTests {
    @Test func callDistillationNeverStoresRawAudioOrTranscriptPaths() {
        let payload = MeetingCallUnderstandingBuilder().callDistilledPayload(
            entityDisplayName: "Mother",
            topic: "family logistics and evening plan",
            taskCandidates: ["plan evening"],
            entitiesMentioned: ["wife"],
            actionItemCount: 1,
            lexicalTone: "friendly",
            whisperConfidence: 0.82,
            evidenceEventIDs: ["event-a"]
        )

        #expect(payload["content_kind"] == "call_distilled")
        #expect(payload["raw_audio_retained"] == "false")
        #expect(payload["raw_transcript_retained"] == "false")
        #expect(payload["audio_path"] == "")
        #expect(payload["transcript_path"] == "")
        #expect(payload["tone_source"] == "lexical_only")
    }

    @Test func audioCapturePolicyRequiresVisibleIndicator() {
        let payload = MeetingCallUnderstandingBuilder().audioCaptureStatePayload(
            episodeKind: "call",
            systemAudioEnabled: true,
            microphoneEnabled: true,
            captionsAvailable: false
        )

        #expect(payload["visible_indicator"] == "true")
        #expect(payload["debug_raw_storage"] == "forbidden")
        #expect(payload["raw_audio_retained"] == "false")
    }

    @Test func actionItemsAreParaphraseOnlyWithEvidence() {
        let payload = MeetingCallUnderstandingBuilder().actionItemPayload(
            text: "Ask Denis to send the final report by Friday",
            requesterEntity: "Andrey",
            addressee: "me",
            dueHint: "Friday",
            evidenceEventIDs: ["context-1"]
        )

        #expect(payload["quote_policy"] == "paraphrase_no_raw_call_transcript")
        #expect(payload["evidence_event_ids"] == "context-1")
        #expect(payload["raw_transcript_retained"] == "false")
    }
}

struct ObjectPresenceBuilderTests {
    @Test func phoneInHandBecomesShadowEvidenceOnly() {
        let payload = ObjectPresenceBuilder().payload(
            objectClass: "cell phone",
            inHand: true,
            durationSeconds: 12,
            confidence: 0.88
        )

        #expect(payload?["object_class"] == "cell phone")
        #expect(payload?["evidence_role"] == "screen_break_or_wandering_disambiguation")
        #expect(payload?["display_eligible"] == "false")
        #expect(payload?["frame_retained"] == "false")
    }

    @Test func bottleOrFoodBecomesRefuelEvidence() {
        let payload = ObjectPresenceBuilder().payload(
            objectClass: "bottle",
            inHand: true,
            durationSeconds: 30,
            confidence: 0.75
        )

        #expect(payload?["evidence_role"] == "refuel_break_candidate")
    }

    @Test func headphonesAreRejectedBecauseAudioRouteIsBetter() {
        let payload = ObjectPresenceBuilder().payload(
            objectClass: "headphones",
            inHand: false,
            durationSeconds: 30,
            confidence: 0.91
        )

        #expect(payload == nil)
    }
}
