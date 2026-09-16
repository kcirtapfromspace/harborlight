#!/usr/bin/env python3
"""Generate data/loan_applications.csv, the synthetic Harborlight source.

Every row is synthetic. Harborlight is a fictional lender; no real borrower
identities, credit scores or lending decisions exist anywhere in this data.

The generator is deterministic: a fixed seed and a fixed base timestamp mean
running it twice produces byte-identical output, so the numbers quoted in the
README stay true. The window covers two hours of seeded synthetic application
history, matching the hosted demo's dataset description.

Partner-channel events stop 15 minutes before the end of the history. That gap
is deliberate: the analyst must report "unavailable (0 samples)" for partner in
the final window, never 0. Unavailable is different from zero.
"""

import csv
import random
from datetime import datetime, timedelta, timezone
from pathlib import Path

SEED = 20261174
BASE = datetime(2026, 9, 15, 12, 0, 0, tzinfo=timezone.utc)
DURATION_SECS = 7205  # two hours of seeded history, plus the seed offset
PARTNER_BLACKOUT_SECS = 900  # no partner events in the final 15 minutes
EVENT_COUNT = 640

CHANNELS = [("web", 0.55), ("mobile", 0.35), ("partner", 0.10)]
REGIONS = [("northeast", 0.30), ("southeast", 0.20), ("midwest", 0.20), ("west", 0.30)]
PRODUCTS = [("personal_loan", 0.45), ("auto_loan", 0.35), ("credit_card", 0.20)]

# Per-channel probabilities. Partner has the highest manual review *rate*;
# web produces the most reviews by *count*. The channel with the most reviews
# may differ from the channel with the highest review rate.
REVIEW_PROB = {"web": 0.038, "mobile": 0.052, "partner": 0.125}
MISMATCH_PROB = {"web": 0.010, "mobile": 0.016, "partner": 0.022}
PROCESSING_MEAN = {"web": 31.0, "mobile": 44.0, "partner": 58.0}


def pick(rng, table):
    r = rng.random()
    acc = 0.0
    for value, weight in table:
        acc += weight
        if r <= acc:
            return value
    return table[-1][0]


def main():
    rng = random.Random(SEED)
    rows = []
    for _ in range(EVENT_COUNT):
        channel = pick(rng, CHANNELS)
        limit = DURATION_SECS - (PARTNER_BLACKOUT_SECS if channel == "partner" else 0)
        offset = rng.uniform(0, limit)
        ts = BASE + timedelta(seconds=offset)
        mismatch = rng.random() < MISMATCH_PROB[channel]
        # An identity mismatch always routes to manual review.
        review = mismatch or rng.random() < REVIEW_PROB[channel]
        processing = max(5.0, rng.gauss(PROCESSING_MEAN[channel], 8.0))
        rows.append(
            {
                "ts_utc": ts.strftime("%Y-%m-%dT%H:%M:%SZ"),
                "channel": channel,
                "region": pick(rng, REGIONS),
                "product": pick(rng, PRODUCTS),
                "manual_review": int(review),
                "identity_mismatch": int(mismatch),
                "processing_seconds": f"{processing:.1f}",
            }
        )
    rows.sort(key=lambda r: r["ts_utc"])

    out = Path(__file__).resolve().parent / "loan_applications.csv"
    with out.open("w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    print(f"wrote {len(rows)} synthetic events to {out}")


if __name__ == "__main__":
    main()
