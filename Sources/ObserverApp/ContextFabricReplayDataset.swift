import Foundation

struct ContextFabricReplayFixture: Equatable {
    let id: Int
    let name: String
    let group: String
    let expectedObservations: [String]
    let expectedEvidenceLinks: [String]
    let expectedEpisodeBoundaries: String
    let expectedActivityThread: String
    let allowedAssignments: [String]
    let forbiddenAssignments: [String]
    let expectedTransitions: [String]
    let maximumCausalMaturity: String
    let expectedActiveSeconds: Double
    let expectedUnassignedSeconds: Double
}

enum ContextFabricReplayDataset {
    static let fixtures: [ContextFabricReplayFixture] = [
        fixture(1, "cross_app_design_ai_codex", "context", ["figma", "chatgpt", "codex"], ["same_artifact", "same_topic"], "one episode", "Observer/Libertex design thread", ["same_context"], ["split_by_app"], ["task_resumed"], "plausible_mechanism", 3600, 0),
        fixture(2, "two_chatgpt_tasks", "context", ["chatgpt prompt A", "chatgpt prompt B"], ["different_topic"], "two episodes", "two threads", ["different_context"], ["same_app_same_thread"], [], "sequence", 1800, 900),
        fixture(3, "same_task_two_parts_one_day", "context", ["morning artifact", "afternoon artifact"], ["same_artifact"], "two episodes", "same thread", ["same_context"], ["unassigned"], ["task_resumed"], "association", 2700, 0),
        fixture(4, "next_day_continuation", "context", ["day1 artifact", "day2 artifact"], ["same_repository"], "cross-day episodes", "same thread", ["same_context"], ["new_thread_by_day"], ["task_resumed"], "association", 2400, 0),
        fixture(5, "app_switch_without_context_switch", "context", ["figma", "browser", "chat"], ["clipboard_route"], "one episode", "same thread", ["same_context"], ["split_by_app"], [], "sequence", 1500, 0),
        fixture(6, "topic_switch_one_app", "context", ["same app", "different topic"], ["topic_delta"], "two episodes", "different threads", ["different_context"], ["same_app_same_thread"], [], "sequence", 1200, 600),
        fixture(7, "same_filename_different_repos", "context", ["file A", "file B"], ["repository_root"], "two episodes", "two threads", ["different_context"], ["same_name_merge"], [], "sequence", 1800, 0),
        fixture(8, "figma_artifact_multiday", "context", ["figma file day1", "figma file day3"], ["same_figma_file"], "cross-day episodes", "same thread", ["same_context"], ["temporal_only"], ["task_resumed"], "association", 4200, 0),
        fixture(9, "clipboard_links_apps", "context", ["copy", "paste"], ["clipboard_route"], "one episode", "same thread", ["same_context"], ["unassigned"], [], "sequence", 900, 0),
        fixture(10, "near_time_no_semantic_link", "context", ["tab A", "tab B"], ["temporal_only"], "two episodes", "unassigned or separate", ["unassigned", "different_context"], ["same_context"], [], "sequence", 600, 600),
        fixture(11, "semantic_link_after_long_break", "context", ["artifact before break", "artifact after break"], ["same_artifact"], "two linked episodes", "same thread", ["same_context"], ["new_thread_by_gap"], ["task_resumed"], "association", 1800, 0),
        fixture(12, "retroactive_unassigned_link", "context", ["unknown first", "later artifact"], ["retroactive_artifact"], "two episodes", "same thread after relink", ["same_context"], ["stay_unassigned"], [], "sequence", 1600, 500),
        fixture(13, "phone_interruption", "camera", ["phone", "gaze away", "input pause"], ["camera_scene", "input"], "interruption slice", "same prior thread", ["unassigned"], ["phone_causes_task_truth"], ["task_interrupted"], "sequence", 300, 300),
        fixture(14, "phone_without_interruption", "camera", ["phone", "input continues"], ["camera_contradicted_by_input"], "same episode", "same thread", ["same_context"], ["phone_interruption"], [], "sequence", 900, 0),
        fixture(15, "bottle_hand_near_mouth", "camera", ["bottle", "hand_near_mouth"], ["camera_scene"], "micro break", "same thread", ["same_context"], ["drinking_fact"], [], "sequence", 60, 0),
        fixture(16, "hand_near_mouth_only", "camera", ["hand_near_mouth"], ["camera_scene"], "same episode", "same thread", ["same_context"], ["eating_or_drinking_fact"], [], "sequence", 300, 0),
        fixture(17, "headphones_with_call", "camera", ["headphones", "call metadata"], ["camera_scene", "call"], "meeting slice", "communication thread", ["same_context"], ["music_preference"], [], "association", 1200, 0),
        fixture(18, "headphones_without_call", "camera", ["headphones", "media"], ["media"], "same episode", "same thread", ["same_context"], ["call_fact"], [], "sequence", 900, 0),
        fixture(19, "user_absent", "camera", ["face_absent", "input_idle"], ["presence", "input"], "away interval", "unassigned", ["unassigned"], ["work_active"], ["task_interrupted"], "sequence", 0, 0),
        fixture(20, "temporary_face_missing", "camera", ["face_missing", "input_active"], ["presence_contradiction"], "same episode", "same thread", ["same_context"], ["away"], [], "sequence", 600, 0),
        fixture(21, "user_returned", "camera", ["user_present", "input_resumes"], ["presence", "input"], "return slice", "previous thread", ["same_context"], ["security_incident"], ["task_resumed"], "association", 500, 0),
        fixture(22, "another_person_nearby", "camera", ["another_person"], ["camera_scene"], "security candidate", "unassigned", ["unassigned"], ["owner_return"], [], "sequence", 0, 0),
        fixture(23, "camera_contradicts_screen_input", "camera", ["camera_away", "typing"], ["contradiction"], "same episode", "same thread", ["same_context"], ["away_fact"], [], "sequence", 900, 0),
        fixture(24, "same_frame_multiple_cues", "camera", ["smile", "mouth", "face"], ["same_frame_not_independent"], "same episode", "same thread", ["same_context"], ["multi_channel_fusion"], [], "sequence", 300, 0),
        fixture(25, "idle_in_open_app", "time", ["app open", "idle"], ["input"], "idle slice", "same or unassigned", ["unassigned"], ["active_work"], [], "sequence", 0, 600),
        fixture(26, "background_media", "time", ["media", "no focus"], ["media"], "non-active slice", "unassigned", ["unassigned"], ["media_work"], [], "sequence", 0, 0),
        fixture(27, "video_call_no_input", "time", ["call", "presence"], ["call", "camera"], "meeting slice", "communication", ["same_context"], ["idle"], [], "association", 1800, 0),
        fixture(28, "two_displays", "time", ["main", "service display"], ["display_role"], "same episode", "same thread", ["same_context"], ["two_tasks_by_display"], [], "sequence", 1200, 0),
        fixture(29, "work_across_midnight", "time", ["late", "next day"], ["observation_window"], "split by day report", "same thread", ["same_context"], ["double_count"], [], "sequence", 1800, 0),
        fixture(30, "timezone_change", "time", ["timezone"], ["schedule"], "coverage adjusted", "same thread", ["same_context"], ["false_gap"], [], "sequence", 600, 0),
        fixture(31, "sensor_gap", "time", ["gap"], ["coverage"], "low coverage", "unassigned gap", ["unassigned"], ["filled_time"], [], "sequence", 0, 0),
        fixture(32, "low_coverage_day", "time", ["coverage"], ["coverage_warning"], "report warning", "threads with warning", ["unassigned"], ["confident_totals"], [], "sequence", 600, 600),
        fixture(33, "idempotent_rebuild", "time", ["rebuild"], ["same_ids"], "no duplicates", "same threads", ["same_context"], ["duplicate_assignment"], [], "sequence", 1000, 0),
        fixture(34, "overlapping_app_intervals", "time", ["overlap"], ["interval_normalization"], "non-overlap slices", "same thread", ["same_context"], ["double_count"], [], "sequence", 1000, 0),
        fixture(35, "bad_output_correction_loop", "causal", ["bad result", "correction"], ["transition", "content"], "correction episode", "same thread", ["same_context"], ["static_state_cause"], ["correction_loop_started"], "plausible_mechanism", 1200, 0),
        fixture(36, "bad_output_no_correction_loop", "causal", ["bad result", "abandoned"], ["outcome"], "abandoned", "same or unassigned", ["unassigned"], ["correction_loop"], [], "sequence", 500, 500),
        fixture(37, "technical_bug_not_semantic_problem", "causal", ["bug", "screen glitch"], ["system"], "bug episode", "technical thread", ["same_context"], ["personal_friction_truth"], ["friction_detected"], "sequence", 900, 0),
        fixture(38, "social_chat_recharge", "causal", ["chat", "smile", "faster return"], ["communication", "subsequent_behavior"], "social episode + aftermath", "social thread", ["same_context"], ["chat_always_distracts"], ["task_resumed"], "association", 900, 0),
        fixture(39, "social_chat_drain", "causal", ["chat", "slow return"], ["communication", "subsequent_behavior"], "social episode + aftermath", "social thread", ["same_context"], ["chat_recharge"], ["task_interrupted"], "association", 500, 300),
        fixture(40, "social_chat_no_change", "causal", ["chat", "stable work"], ["communication", "subsequent_behavior"], "social episode", "social thread", ["same_context"], ["causal_effect"], [], "sequence", 900, 0)
    ]

    private static func fixture(
        _ id: Int,
        _ name: String,
        _ group: String,
        _ observations: [String],
        _ links: [String],
        _ boundaries: String,
        _ thread: String,
        _ allowed: [String],
        _ forbidden: [String],
        _ transitions: [String],
        _ maturity: String,
        _ active: Double,
        _ unassigned: Double
    ) -> ContextFabricReplayFixture {
        .init(
            id: id,
            name: name,
            group: group,
            expectedObservations: observations,
            expectedEvidenceLinks: links,
            expectedEpisodeBoundaries: boundaries,
            expectedActivityThread: thread,
            allowedAssignments: allowed,
            forbiddenAssignments: forbidden,
            expectedTransitions: transitions,
            maximumCausalMaturity: maturity,
            expectedActiveSeconds: active,
            expectedUnassignedSeconds: unassigned
        )
    }
}
