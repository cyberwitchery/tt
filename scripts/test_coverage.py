import contextlib
import io
import unittest

from check_coverage import REQUIRED, check


class CoverageTests(unittest.TestCase):
    def report(self):
        return {"targets": [{"name": "tt.app", "files": [
            {"path": f"/any/folder/{name}", "coveredLines": 100, "executableLines": 100}
            for name in REQUIRED
        ]}]}

    def failures(self, report):
        with contextlib.redirect_stdout(io.StringIO()):
            return check(report)

    def test_file_location_does_not_decide_coverage(self):
        self.assertEqual(self.failures(self.report()), [])

    def test_high_aggregate_does_not_hide_an_untested_coordinator(self):
        report = self.report()
        app_state = next(f for f in report["targets"][0]["files"] if f["path"].endswith("AppState.swift"))
        app_state["coveredLines"] = 79
        self.assertEqual(self.failures(report), ["AppState.swift: below 80%"])

    def test_missing_or_empty_file_fails(self):
        report = self.report()
        missing = report["targets"][0]["files"].pop()
        self.assertEqual(self.failures(report), [missing["path"].split("/")[-1] + ": missing coverage"])
        report = self.report()
        report["targets"][0]["files"][0]["executableLines"] = 0
        self.assertEqual(len(self.failures(report)), 1)

    def test_test_target_cannot_supply_application_coverage(self):
        report = self.report()
        report["targets"][0]["name"] = "ttTests.xctest"
        self.assertEqual(len(self.failures(report)), len(REQUIRED))


if __name__ == "__main__":
    unittest.main()
