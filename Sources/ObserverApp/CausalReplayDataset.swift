import Foundation

struct CausalReplayFixture: Codable, Equatable {
    let id: String
    let scenario: String
    let expectedEpisodeBoundaries: String
    let expectedTransition: String
    let allowedAntecedents: [String]
    let forbiddenAntecedents: [String]
    let expectedMechanism: String
    let requiredAlternative: String
    let maximumMaturityLevel: String
    let forbiddenCausalClaims: [String]
}

enum CausalReplayDataset {
    static let fixtures: [CausalReplayFixture] = [
        fixture(1, "app_switch_continues_one_task", "one episode across ChatGPT, Codex, Observer", "correction_loop_started", ["surface output", "same unresolved question"], ["new unrelated task"], "same artifact stays under review", "planned next iteration", "plausible_mechanism", ["app switch caused the task"]),
        fixture(2, "app_switch_means_new_task", "split after semantic topic changes", "topic_changed", ["new topic", "new artifact"], ["same app switch"], "new goal replaces previous goal", "tab switch within same task", "association", ["Chrome caused the change"]),
        fixture(3, "failed_output_triggers_correction", "one review episode", "correction_loop_started", ["failed output", "quality mismatch"], ["camera-only frustration"], "result fails expected abstraction level", "technical bug caused rework", "plausible_mechanism", ["user was angry because of output"]),
        fixture(4, "failed_output_no_correction", "review episode closes without rework", "task_completed", ["accepted output"], ["failed output as cause"], "output was accepted or ignored", "correction may happen later", "sequence", ["failure caused correction"]),
        fixture(5, "repeated_requirement_correction", "one long correction episode", "correction_loop_repeated", ["repeated requirement wording"], ["single typo"], "same requirement returns after each attempt", "planned refinement", "plausible_mechanism", ["one bad line caused everything"]),
        fixture(6, "technical_bug_not_semantic_problem", "bug episode separate from meaning episode", "blocked", ["error state", "crash"], ["semantic quality mismatch"], "tool bug interrupts work", "user misunderstood requirements", "association", ["meaning problem caused bug"]),
        fixture(7, "social_chat_recovery", "social episode then work episode", "task_resumed", ["positive chat aftermath"], ["chat text alone"], "after chat input returns faster", "time break alone helped", "association", ["chat definitely improved mood"]),
        fixture(8, "social_chat_distraction", "communication episode absorbs work span", "task_interrupted", ["repeated returns to chat"], ["positive smile"], "chat prevents return to task", "task already ended", "association", ["chat always distracts"]),
        fixture(9, "social_chat_no_change", "communication episode with flat aftermath", "unknown_change", ["flat input delta"], ["chat caused recovery"], "no observable delta after chat", "effect too small to see", "sequence", ["chat affected productivity"]),
        fixture(10, "pause_helps_return", "idle gap inside same topic", "task_resumed", ["same topic after pause"], ["new app only"], "pause preserves context and input resumes", "external reminder", "association", ["pause always helps"]),
        fixture(11, "pause_loses_context", "idle then new formulation", "task_interrupted", ["reformulation after pause"], ["same stable flow"], "context needs reconstruction after idle", "new task intentionally started", "association", ["pause caused bad state"]),
        fixture(12, "long_single_app_work", "one app one episode", "task_completed", ["stable content and input"], ["no switches"], "same context continues", "hidden tab change", "sequence", ["no switching means flow"]),
        fixture(13, "return_after_idle", "same task resumes after away", "task_resumed", ["same content topic", "new input"], ["face absent alone"], "same unresolved item remains active", "new task looks similar", "association", ["absence caused recovery"]),
        fixture(14, "topic_change_inside_chatgpt", "split inside same app", "topic_changed", ["new prompt topic"], ["same app"], "semantic topic changes despite same app", "continuation of old question", "association", ["same app means same task"]),
        fixture(15, "camera_contradicts_text", "one episode with contradiction", "emotional_tone_shift", ["text evidence"], ["smile cue alone"], "camera cue stays contradiction until content agrees", "camera false positive", "sequence", ["smile proves positive reaction"]),
        fixture(16, "correlated_cues_one_source", "one episode", "friction_detected", ["single rule source"], ["multiple independent channels"], "same source must not inflate confidence", "hidden independent evidence", "sequence", ["three camera cues prove it"]),
        fixture(17, "early_episode_cause", "cause near episode start", "correction_loop_started", ["initial weak criteria"], ["nearest app switch"], "early unresolved condition enables later loop", "later bug caused it", "plausible_mechanism", ["nearest event is the cause"]),
        fixture(18, "temporal_without_semantic", "events close but unrelated", "unknown_change", ["time proximity only"], ["semantic cause"], "temporal link is insufficient", "unseen semantic link", "sequence", ["nearby event caused transition"]),
        fixture(19, "semantic_weak_temporal", "cause distant but same topic", "correction_loop_started", ["same unresolved requirement"], ["nearest unrelated event"], "semantic continuity beats proximity", "memory of issue was coincidental", "association", ["distant cause is proven"]),
        fixture(20, "counterexample_to_pattern", "similar A without B", "unknown_change", ["counterexample"], ["pattern promotion"], "validation weakens pattern", "measurement missed B", "association", ["pattern is universal"]),
        fixture(21, "visual_comparison_resolves_uncertainty", "design and browser one episode", "unblocked", ["side-by-side comparison"], ["random switch"], "visual comparison clarifies decision", "answer came from memory", "association", ["Figma caused clarity"]),
        fixture(22, "ambiguous_requirement_causes_rework", "work loop with unclear brief", "correction_loop_repeated", ["ambiguous requirement"], ["tone cue"], "unclear criteria force rework", "implementation bug", "plausible_mechanism", ["user emotion caused rework"]),
        fixture(23, "llm_escalation_after_failed_iteration", "AI model switch same task", "correction_loop_repeated", ["failed iteration", "model switch"], ["new task"], "same problem moves to another model", "user wanted second opinion anyway", "plausible_mechanism", ["model switch means new task"]),
        fixture(24, "reading_not_idle", "static screen with reading evidence", "unknown_change", ["scroll and content freshness"], ["no input alone"], "lack of typing can still be active reading", "user looked away", "sequence", ["no input means idle"]),
        fixture(25, "sanitary_status_rejected", "Observer QA episode", "correction_loop_started", ["L0/L1 status seen"], ["presence status"], "low abstraction output fails product requirement", "the issue was layout not wording", "plausible_mechanism", ["status caused anger"])
    ]

    private static func fixture(
        _ index: Int,
        _ scenario: String,
        _ boundaries: String,
        _ transition: String,
        _ allowed: [String],
        _ forbidden: [String],
        _ mechanism: String,
        _ alternative: String,
        _ maxMaturity: String,
        _ forbiddenClaims: [String]
    ) -> CausalReplayFixture {
        CausalReplayFixture(
            id: String(format: "causal-%02d", index),
            scenario: scenario,
            expectedEpisodeBoundaries: boundaries,
            expectedTransition: transition,
            allowedAntecedents: allowed,
            forbiddenAntecedents: forbidden,
            expectedMechanism: mechanism,
            requiredAlternative: alternative,
            maximumMaturityLevel: maxMaturity,
            forbiddenCausalClaims: forbiddenClaims
        )
    }
}
