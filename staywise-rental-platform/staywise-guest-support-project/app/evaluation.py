"""Integration checks run from the Integration checks page inside Snowflake.

The deterministic checks call real stored procedures. Optional agent checks use
real Cortex responses, so a failure is shown as a failure rather than simulated.
"""
import json
from pathlib import Path
from datetime import datetime, timezone

from app.agent import CortexModel, run_agent
from app.settings import MODEL
from app.tools import SnowflakeTools

# The first seven cases cover availability, pets, prices, and incomplete calendars.
# Agent cases exercise tool selection, citations, and the complete recovery flow.
# Evaluation inputs are packaged under data/ alongside the other source assets.
CASES_PATH = Path(__file__).resolve().parents[1] / "data" / "evaluation_cases.json"


def run_checks(session, include_agent=False):
    """Execute deployed-tool checks and optional live agent evaluations.

    Args:
        session (Session): Active Snowpark session with the application's grants.
        include_agent (bool): If true, also run five model-backed scenarios;
            otherwise run only the seven deterministic procedure scenarios.

    Returns:
        list[dict]: One result per selected case, containing case, passed, detail,
        and checked_at in UTC. A failed case does not stop later cases.

    Raises:
        OSError: The packaged data/evaluation_cases.json file cannot be read.
        json.JSONDecodeError: The evaluation data is not valid JSON.

    Notes:
        Reads real Snowflake objects. Agent scenarios consume AI credits. Case
        failures are captured as results; failures loading the case file propagate.
        Results are returned to Streamlit for display/export and are not saved to
        an application filesystem or written to booking tables.
    """
    tools = SnowflakeTools(session)
    outcomes = []
    cases = json.loads(CASES_PATH.read_text(encoding="utf-8"))
    for case in cases:
        # Keep billable model checks an explicit user action.
        if case["kind"] == "agent" and not include_agent:
            continue
        try:
            if case["kind"] == "tool":
                result = tools.quote_stay_option(
                    case["listing_id"], case.get("check_in", "2026-09-23"),
                    case.get("check_out", "2026-09-25"), 2, case["pet_type"],
                    case["mode"], case["booking_id"]
                )
                assert result["status"] == case["expected_status"], result
                if "expected_total" in case:
                    assert result["total"] == case["expected_total"], result
            else:
                # Keep identical constraints across repetitions to compare behavior.
                constraints = dict(booking_id="B-1042", check_in="2026-09-23",
                    check_out="2026-09-25", neighborhood="Candolim", guests=2,
                    pet_type="cat", max_total=case.get("budget", 9000),
                    resolution=case.get("resolution", False))
                result = run_agent(case["question"], constraints, CortexModel(session, MODEL), tools)
                assert result["status"] == "complete", result
                observed = {obs["tool"] for obs in result["observations"]}
                assert set(case["required_tools"]) <= observed, observed
                # Check evidence and numeric results, not just fluent answer text.
                for expected in case.get("expected_text", []):
                    assert expected.lower() in result["answer"].lower(), result["answer"]
                if "required_document" in case:
                    assert any(p["doc_id"] == case["required_document"] for p in result["citations"])
                if "expected_listing" in case:
                    assert result["quote"]["listing_id"] == case["expected_listing"]
                    assert result["quote"]["total"] == case["expected_total"]
                if case.get("expect_no_quote"):
                    assert result["quote"] is None
            passed, detail = True, result
        except Exception as error:
            # One failed case must not hide the outcome of all remaining cases.
            passed, detail = False, str(error)
        outcomes.append({"case": case["id"], "passed": passed, "detail": str(detail),
                         "checked_at": datetime.now(timezone.utc).isoformat()})
    return outcomes
