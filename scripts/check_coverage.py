#!/usr/bin/env python3
"""Require coverage for each named unit of application logic, wherever it lives."""
import json
import os
from pathlib import Path
import sys

REQUIRED = {
    "AppState.swift", "TimeTracker.swift", "Models.swift", "TimeMath.swift",
    "DayCalendar.swift", "EntryEditor.swift", "Reports.swift", "CSVExporter.swift",
    "DatabaseManager.swift", "ProjectRepository.swift", "TimeEntryRepository.swift",
    "KeyboardShortcut.swift", "WeekChartModel.swift",
}


def check(report, minimum=80):
    files = {}
    for target in report.get("targets", []):
        if target.get("name") != "tt.app":
            continue
        for file in target.get("files", []):
            name = Path(file["path"]).name
            if name in REQUIRED:
                files[name] = file
    failures = []
    for name in sorted(REQUIRED):
        file = files.get(name)
        if not file or not file.get("executableLines"):
            failures.append(f"{name}: missing coverage")
            continue
        percent = 100 * file["coveredLines"] / file["executableLines"]
        print(f"{name}: {percent:.1f}% (minimum {minimum:g}%)")
        if percent < minimum:
            failures.append(f"{name}: below {minimum:g}%")
    return failures


if __name__ == "__main__":
    with open(sys.argv[1]) as source:
        failures = check(json.load(source), float(os.environ.get("MIN_COVERAGE", "80")))
    for failure in failures:
        print(f"::error::{failure}")
    sys.exit(bool(failures))
