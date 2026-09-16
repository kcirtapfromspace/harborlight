#!/usr/bin/env python3
"""The Harborlight analyst agent. A stand-in for the coding agent you already run.

It reads the synthetic loan-application history and reports the manual review
rate. `report` behaves; `debug-env` is the careless habit this quickstart is
about: dumping the environment "for debugging" puts every inherited secret in
the transcript.

Harborlight is a fictional lender. All values here are synthetic.
"""

import csv
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / "data" / "loan_applications.csv"
WINDOWS = [("last 15 minutes", 15), ("last 60 minutes", 60)]
CHANNELS = ["web", "mobile", "partner"]


def load_rows():
    with DATA.open(newline="") as fh:
        rows = list(csv.DictReader(fh))
    for row in rows:
        row["ts"] = datetime.strptime(row["ts_utc"], "%Y-%m-%dT%H:%M:%SZ").replace(
            tzinfo=timezone.utc
        )
    return rows


def rate_line(label, reviews, samples):
    if samples == 0:
        return f"  {label}: unavailable (0 samples)"
    rate = reviews / samples * 100
    return f"  {label}: manual review rate {rate:.2f} %, {reviews} reviews from {samples} applications"


def report():
    token = os.environ.get("HARBORLIGHT_SOURCE_TOKEN", "")
    if not token:
        print(
            "error: HARBORLIGHT_SOURCE_TOKEN is not set; the synthetic source requires a token",
            file=sys.stderr,
        )
        return 1

    rows = load_rows()
    as_of = max(row["ts"] for row in rows)
    print("Harborlight portfolio report (synthetic data)")
    print(f"  as of {as_of.strftime('%Y-%m-%dT%H:%M:%SZ')} (data time)")
    print("  source token: present (value withheld)")

    any_unavailable = False
    for label, minutes in WINDOWS:
        start = as_of - timedelta(minutes=minutes)
        window = [row for row in rows if row["ts"] > start]
        reviews = sum(int(row["manual_review"]) for row in window)
        print(f"\n{label}:")
        print(rate_line("all channels", reviews, len(window)))
        most_reviews = None
        highest_rate = None
        for channel in CHANNELS:
            rows_c = [row for row in window if row["channel"] == channel]
            reviews_c = sum(int(row["manual_review"]) for row in rows_c)
            print(rate_line(channel, reviews_c, len(rows_c)))
            if rows_c:
                if most_reviews is None or reviews_c > most_reviews[1]:
                    most_reviews = (channel, reviews_c)
                rate_c = reviews_c / len(rows_c)
                if highest_rate is None or rate_c > highest_rate[1]:
                    highest_rate = (channel, rate_c)
            else:
                any_unavailable = True

    if any_unavailable:
        print("\nUnavailable is different from zero.")
    if most_reviews and highest_rate and most_reviews[0] != highest_rate[0]:
        print(
            "Keep count and rate questions distinct: the channel with the most "
            "reviews may differ from the channel with the highest review rate."
        )
    return 0


def debug_env():
    # The careless habit. Everything the process inherited, printed.
    print("environment dump (careless):")
    for key in sorted(os.environ):
        print(f"  {key}={os.environ[key]}")
    return 0


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in {"report", "debug-env"}:
        print("usage: analyst.py report|debug-env", file=sys.stderr)
        return 2
    return report() if sys.argv[1] == "report" else debug_env()


if __name__ == "__main__":
    sys.exit(main())
