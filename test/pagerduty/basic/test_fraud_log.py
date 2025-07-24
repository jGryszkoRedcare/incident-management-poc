import time, subprocess, pytest, os
from tests.pagerduty.pd_helpers import (
    TEAM_MAP, wait_for_assignment_and_ack
)

FRAUD_LOG = 'FRAUD_ATTEMPT test_id=pytest_demo'
TEAM_ID   = TEAM_MAP["payment"]
ENGS      = ["janusz.gryszko@redcare-pharmacy.com", "daniel.krones@hotmail.com", "eduardo.galvan@redcare-pharmacy.com"]

def _emit_log():
    # simple: echo into the container's stdout
    cmd = ["docker", "compose", "exec", "-T", "fraud-detection",
           "sh", "-c", f'echo "{FRAUD_LOG}" 1>&2']
    subprocess.check_call(cmd)

@pytest.mark.smoke
def test_fraud_log_triggers_incident():
    _emit_log()
    time.sleep(45)        # 15 s scrape + 30 s alert `for:`

    assert wait_for_assignment_and_ack(TEAM_ID, ENGS[0], 60) \
        or wait_for_assignment_and_ack(TEAM_ID, ENGS[1], 60) \
        or wait_for_assignment_and_ack(TEAM_ID, ENGS[2], 60), \
        "No engineer in escalation chain acknowledged fraud attempt"
