import pytest, time, os
from test.pagerduty.flag_helpers import temporary_flag
from test.pagerduty.pd_helpers   import (
    TEAM_MAP,
    REAL_EMAILS,
    wait_for_assignment_and_ack,
    acknowledge_incident_as,
)


def test_ad_failure_triggers_oncall():
    team_id = TEAM_MAP["ad"]

    with temporary_flag("adFailure", "on"):
        # give the alert some breathing room (Prom scrape + Grafana rule eval)
        time.sleep(30)

        assert wait_for_assignment_and_ack(team_id, "alice@example.com", 90) \
            or wait_for_assignment_and_ack(team_id, "bob@example.com", 90), \
            "No engineer acknowledged ad‑service failure"


# ── per‑flag config table ----------------------------------------------------
engineer_order = ["AllTeams Engineer1", "AllTeams Engineer2", "AllTeams Engineer3"]
FLAGS = [
    # flag_name                            team_key          engineer order
    ("adServiceFailure",                   "shopstack",      engineer_order),
    ("adServiceManualGc",                  "shopstack",      engineer_order),
    ("adServiceHighCpu",                   "shopstack",      engineer_order),
    ("cartServiceFailure",                 "shopstack",      engineer_order),
    ("productCatalogFailure",              "shopstack",      engineer_order),
    ("recommendationServiceCacheFailure",  "shopstack",      engineer_order),
    ("kafkaQueueProblems",                 "infraops",       engineer_order),
    ("imageSlowLoad",                      "shopstack",      engineer_order),
    ("loadgeneratorFloodHomepage",         "shopstack",      engineer_order),
    ("paymentServiceFailure",              "finguard",       engineer_order),
    ("paymentServiceUnreachable",          "finguard",       engineer_order),
]


@pytest.mark.parametrize("flag,team_key,order", FLAGS)
def test_feature_flag_triggers_and_ack(flag, team_key, order):
    team_id = TEAM_MAP[team_key]

    with temporary_flag(flag, "on"):
        time.sleep(30)                       # give Grafana rule time to fire

        assert wait_for_assignment_and_ack(team_id, REAL_EMAILS[0], 90) \
            or wait_for_assignment_and_ack(team_id, REAL_EMAILS[1], 90), \
            f"No ack for flag {flag}"


def test_payment_failure_escalation():
    team_id = TEAM_MAP["finguard"]
    eng1, eng2, eng3 = FLAGS[2]

    with temporary_flag("paymentServiceFailure", "on"):
        time.sleep(30)                       # wait for alert → incident

        # 1 Wait up to 60 s for *assignment* to engineer 1 (but we expect no ack)
        assigned = wait_for_assignment_and_ack(
            team_id, REAL_EMAILS[0], timeout_s=60
        )
        assert assigned is False, "Engineer1 unexpectedly acknowledged"

        # 2 Force engineer 2 to acknowledge via API
        inc_id = acknowledge_incident_as(team_id, REAL_EMAILS[1])
        assert inc_id, "No incident found to acknowledge"

        # 3 Verify engineer 2 shows up as acked
        assert wait_for_assignment_and_ack(
            team_id, REAL_EMAILS[1], timeout_s=30
        ), "Engineer2 did not acknowledge after manual API ack"
