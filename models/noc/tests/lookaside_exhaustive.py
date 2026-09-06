#!/usr/bin/env python3
"""Exhaustive adversarial upper bound for four 1R1W write banks.

The search deliberately allows every credited slot in a bank to arrive in any
lane order.  This is more adversarial than RR/pressure placement, so its result
is a safe bound for tagged reservations.  Each cycle has at most four arrivals
and each nonempty bank completes one write in that same cycle.
"""

from functools import lru_cache
from itertools import product


def arrival_vectors(remaining):
    limits = [min(4, value) for value in remaining]
    target = min(4, sum(remaining))
    for vector in product(*(range(limit + 1) for limit in limits)):
        count = sum(vector)
        # For a maximum-backlog proof it is sufficient to enumerate
        # work-conserving arrival schedules. Replacing an idle arrival slot by
        # an earlier legal arrival cannot reduce pending occupancy.
        if count == target:
            yield vector


def prove(bank_depth):
    initial = tuple(sorted(((bank_depth, 0),) * 4))

    @lru_cache(maxsize=None)
    def search(state):
        remaining = tuple(item[0] for item in state)
        pending = tuple(item[1] for item in state)
        if not any(remaining):
            # No future arrivals: the current pending count is the maximum on
            # the deterministic drain tail.
            return sum(pending)

        best = sum(pending)
        for arrivals in arrival_vectors(remaining):
            next_remaining = tuple(r - a for r, a in zip(remaining, arrivals))
            before_service = tuple(p + a for p, a in zip(pending, arrivals))
            next_pending = tuple(max(0, value - 1) for value in before_service)
            next_state = tuple(sorted(zip(next_remaining, next_pending)))
            best = max(best, sum(next_pending), search(next_state))
        return best

    maximum = search(initial)
    return maximum, search.cache_info().currsize


def main():
    expected = {8: 12, 12: 18}
    for depth in (8, 12):
        maximum, states = prove(depth)
        assert maximum == expected[depth], (depth, maximum)
        print(
            f"Q{depth * 4}: bank_depth={depth} "
            f"max_waiting={maximum} extra_beyond_4_landings={maximum - 4} "
            f"states={states}"
        )


if __name__ == "__main__":
    main()
