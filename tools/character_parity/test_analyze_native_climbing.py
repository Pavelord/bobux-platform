"""Guard against false negative outcomes and contaminated calibration evidence."""

import math
import unittest

from analyze_native_climbing import distribution, summarize_case, summarize_condition


def frame(seq=3, state="Climbing", sensed=False, vy=11.2):
    return {"seq": seq, "phase": "PostSimulation", "sim_s": 1.1, "dt_sim_s": 0.1,
            "state": {"Name": state}, "linear_velocity": [0, vy, 0], "position": [0, 4, 1],
            "input": [0, 0, -1], "sensors": [
                {"mode": mode, "SensedPart": sensed, "HitNormal": [0, 0, 1],
                 "HitFrame": [0], "SensedMaterial": "Plastic"} for mode in ("Ladder", "ClassicLadder")]}


class AnalysisTests(unittest.TestCase):
    def setUp(self):
        self.plan = {"id": "trial", "split": "holdout"}
        self.begin = {"seq": 2, "sim_s": 1.0, "wall_s": 1.0}
        self.result = {"seq": 5, "status": "OBSERVED", "wall_s": 1.2, "post_frames": 1,
                       "max_root_rise": 1.0, "vertical_speed_median": 11.2}

    def test_no_window_is_blocked_not_negative_climbing(self):
        case = summarize_case(self.plan, None, None, [], [], [])
        summary = summarize_condition([case])
        self.assertEqual(case["analysis_status"], "BLOCKED")
        self.assertEqual(summary["climbing_outcomes_valid_trials"], {})
        self.assertEqual(summary["observed_valid_trials"], 0)

    def test_dead_overrides_observed_without_changing_raw_status(self):
        case = summarize_case(self.plan, self.begin, self.result, [frame(state="Dead")], [], [])
        self.assertEqual(case["raw_result_status"], "OBSERVED")
        self.assertEqual(case["analysis_status"], "BLOCKED")
        self.assertEqual(case["dead_post_callbacks"], 1)

    def test_reset_events_are_not_measured_states(self):
        events = [{"seq": 1, "sim_s": 0.1, "old": "Running", "new": "Freefall"},
                  {"seq": 4, "sim_s": 1.1, "old": "Running", "new": "Climbing"}]
        case = summarize_case(self.plan, self.begin, self.result, [frame()], [], events)
        self.assertEqual([e["new"] for e in case["measured_state_event_sequence"]], ["Climbing"])

    def test_pre_simulation_is_not_double_counted(self):
        pre = frame(seq=3)
        pre["phase"] = "PreSimulation"
        case = summarize_case(self.plan, self.begin, self.result, [pre, frame(seq=4)], [], [])
        self.assertEqual(case["post_callbacks"], 1)
        self.assertAlmostEqual(case["climbing_callback_dt_sum_s"], 0.1)

    def test_sensor_nil_and_actual_climbing_are_separate(self):
        case = summarize_case(self.plan, self.begin, self.result, [frame(sensed=False)], [], [])
        self.assertTrue(case["climbing_observed"])
        self.assertEqual(case["sensors"]["Ladder"]["sensor_vs_native_state_counts"],
                         {"sensor_nil__humanoid_Climbing": 1})

    def test_callback_count_mismatch_blocks_trial(self):
        self.result["post_frames"] = 2
        case = summarize_case(self.plan, self.begin, self.result, [frame()], [], [])
        self.assertEqual(case["analysis_status"], "BLOCKED")

    def test_non_finite_values_do_not_enter_distributions(self):
        self.assertEqual(distribution([math.nan, math.inf, None, 1, 3])["median"], 2)


if __name__ == "__main__":
    unittest.main()
