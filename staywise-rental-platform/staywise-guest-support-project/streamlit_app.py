"""StayWise interface, executed by the Streamlit warehouse runtime in Snowflake.

The four pages share curated Snowflake tables and the active Snowpark session.
Only clicking Investigate or Run checks initiates tool/model calls.
"""
import json
from datetime import date

import pandas as pd
import streamlit as st

from snowflake.snowpark.context import get_active_session
from app.settings import MODEL, MAX_TOOL_CALLS, REFERENCE_DATE

# Configure the page before drawing any widget. CSS only styles presentation.
st.set_page_config(page_title="StayWise | Guest support", page_icon="🏡", layout="wide")
st.markdown("""<style>
.block-container {padding-top:4.5rem; max-width:1320px;}
.eyebrow {letter-spacing:.16em; font-size:.75rem; color:#147D80; font-weight:700;}
.hero {font-size:2.5rem; font-weight:750; color:#183E42; margin:.2rem 0;}
.muted {color:#627577; margin-bottom:1.4rem;}
[data-testid="stMetric"] {background:#fff; padding:1rem; border-radius:14px; border:1px solid #e4ece9;}
</style>""", unsafe_allow_html=True)


def get_session():
    """Return the Snowpark session supplied to this Streamlit application.

    Args:
        None.

    Returns:
        Session: The existing Snowflake runtime session. The caller does not own
        its lifecycle and must not close it or replace its authentication.

    Raises:
        SnowparkSessionException: No active Snowflake session is available.
    """
    return get_active_session()


def load_frames():
    """Load the curated datasets used by the booking and operations pages.

    Args:
        None.

    Returns:
        tuple: Three pandas DataFrames: booking context, listing attributes,
        and monthly listing performance. Column names are normalized to lowercase.

    Raises:
        SnowparkSQLException: A required mart is missing or the app cannot read it.

    Notes:
        Executes three fixed SELECT statements on the active session. Results are
        scoped to this page execution and are not cached across application users.
    """
    session = get_session()

    def frame(sql):
        # Snowflake returns uppercase unquoted columns; normalize at the boundary
        # so the rest of the UI uses the same names as the tool results.
        """Execute a fixed application query and normalize its output columns.

        Args:
            sql (str): Developer-defined SELECT statement for a curated mart.

        Returns:
            pandas.DataFrame: Query rows with lowercase column names.

        Raises:
            SnowparkSQLException: Snowflake rejects or cannot execute the query.

        Notes:
            Uses the enclosing load_frames session. Do not pass model-generated SQL
            here; generated queries must pass app.sql_guard.validate_sql first.
        """
        result = session.sql(sql).to_pandas()
        result.columns = result.columns.str.lower()
        return result

    # These are fixed reads. Only the separate Analyst adapter handles generated SQL.
    data = frame("SELECT * FROM STAYWISE_DB.ANALYTICS.MART_BOOKING_CONTEXT")
    listings = frame("SELECT * FROM STAYWISE_DB.ANALYTICS.DIM_LISTING")
    performance = frame("SELECT * FROM STAYWISE_DB.ANALYTICS.MART_LISTING_PERFORMANCE")
    return data, listings, performance


def show_tool_step(observation):
    """Append a completed tool action to the visible investigation status.

    Args:
        observation (dict): Tool observation containing an id and tool name.

    Returns:
        None. Writes the observation label to the current Streamlit container.

    Notes:
        Called after tool execution by run_agent; it displays action metadata,
        not the model's private reasoning or an unverified result.
    """
    st.write(f"{observation['id']} · {observation['tool']}")


# Navigation and context remain visible while a representative changes pages.
st.sidebar.markdown("## 🏡 StayWise")
st.sidebar.caption("Guest support workspace")
page = st.sidebar.radio("Workspace", ["Booking desk", "Stay comparison", "Operations overview", "Integration checks"])
st.sidebar.divider()
st.sidebar.caption("Synthetic dataset · Goa · INR")
st.sidebar.caption("Reference date: 18 September 2026")
st.sidebar.caption("Synthetic policies. Quotes exclude taxes.")

st.markdown('<div class="eyebrow">STAYWISE / GUEST EXPERIENCE</div>', unsafe_allow_html=True)
st.markdown('<div class="hero">A better next step for every stay.</div>', unsafe_allow_html=True)
st.markdown('<div class="muted">Understand the booking. Check the details. Recommend with evidence.</div>', unsafe_allow_html=True)
try:
    bookings, listings, performance = load_frames()
except Exception as error:
    st.error(f"Could not load the workspace: {error}")
    st.info("Complete the data-loading and dbt steps in RUNBOOK.md, then check STAYWISE_APP grants.")
    st.stop()

# The booking desk keeps fixed constraints separate from the free-text question.
if page == "Booking desk":
    left, right = st.columns([1, 2], gap="large")
    with left:
        st.subheader("Reservation")
        ids = bookings.booking_id.tolist()
        selected = st.selectbox("Booking ID", ids, index=ids.index("B-1042") if "B-1042" in ids else 0)
        booking = bookings.loc[bookings.booking_id == selected].iloc[0]
        st.markdown(f"**{booking.title}**")
        st.caption(f"{booking.neighborhood} · {booking.listing_id}")
        st.write(f"{booking.check_in} → {booking.check_out}")
        st.write(f"{int(booking.guest_count)} guests · {booking.status}")
        st.divider()
        st.markdown("**Request constraints**")
        start = st.date_input("Extra stay check-in", date(2026, 9, 23))
        end = st.date_input("Extra stay checkout", date(2026, 9, 25))
        neighborhood = st.selectbox("Neighborhood", ["Candolim", "Anjuna", "Panaji"])
        guests = st.number_input("Guests", 1, 6, 2)
        pet = st.selectbox("Pet", ["cat", "dog", "none"])
        budget = st.number_input("Total budget (INR)", 1, 100000, 9000, step=500)
    with right:
        st.subheader("Resolve the request")
        st.caption("Use the form to keep dates, budget, and guest needs explicit.")
        task = st.radio("Question type", ["Stay resolution", "Data or policy question"], horizontal=True)
        pet_sentence = "I am not bringing a pet." if pet == "none" else f"I am traveling with my {pet}."
        question = st.text_area("Guest request", value=f"Can I extend booking {selected} by two nights? If unavailable, find a stay in the same neighborhood for the extra nights, under INR {budget:,} total. {pet_sentence}", height=125)
        run = st.button("Investigate request", type="primary")
        if run:
            from app.agent import CortexModel, run_agent
            from app.tools import SnowflakeTools
            if end <= start:
                st.error("Checkout must follow check-in.")
            else:
                # The agent must preserve these form inputs in every tool call.
                constraints = {"booking_id": selected, "check_in": str(start), "check_out": str(end),
                               "neighborhood": neighborhood, "guests": int(guests), "pet_type": pet,
                               "max_total": float(budget), "resolution": task == "Stay resolution"}
                session = get_session()
                # Each callback displays a completed action; it is not hidden LLM reasoning.
                with st.status("Checking the booking and collecting evidence…", expanded=True) as status:
                    result = run_agent(question, constraints, CortexModel(session, MODEL),
                        SnowflakeTools(session), MAX_TOOL_CALLS,
                        on_step=show_tool_step)
                    status.update(label="Investigation finished", state="complete" if result["status"] == "complete" else "error", expanded=False)
                # Per-viewer state preserves evidence when navigating to comparison.
                st.session_state.result = result
                st.session_state.request = question
                # Logging is useful for request auditing, but failure to log must not hide an answer.
                try:
                    session.sql("INSERT INTO STAYWISE_DB.APP.REQUEST_LOG (request_id, question, result) SELECT ?, ?, PARSE_JSON(?)",
                        params=[result["request_id"], question, json.dumps(result, default=str)]).collect()
                except Exception:
                    st.warning("The answer is available, but its audit log could not be saved. Check REQUEST_LOG INSERT grants.")
        if "result" in st.session_state:
            result = st.session_state.result
            st.caption("Last investigation: " + st.session_state.get("request", ""))
            st.markdown(result["answer"])
            # Only the agent's verified quote is promoted to the price card.
            if result["quote"]:
                st.success(f"Verified quote · INR {result['quote']['total']:,.2f}")
                st.dataframe(pd.DataFrame(result["quote"]["breakdown"].items(), columns=["Charge", "INR"]), hide_index=True)
            # Show the actual retrieved passage so developers can audit the answer.
            for source in result["citations"]:
                with st.expander(f"{source['title']} · page {source['page_number']}"):
                    st.write(source["chunk_text"])
                    st.caption(f"Source: {source['doc_id']} / {source['relative_path']}")
            with st.expander("Tools used and supporting evidence"):
                for observation in result["observations"]:
                    st.markdown(f"**{observation['id']} · {observation['tool']}**")
                    st.json(observation)
            st.download_button("Download investigation", json.dumps(result, indent=2, default=str), "staywise-investigation.json", "application/json")

# Candidate cards distinguish an initial estimate from a fully checked quote.
elif page == "Stay comparison":
    st.subheader("Find the fit, then check the details")
    result = st.session_state.get("result", {})
    candidates = [c for obs in result.get("observations", []) for c in obs.get("result", {}).get("candidates", [])]
    if not candidates:
        st.info("Run a booking investigation to compare live candidates. The catalogue below is for browsing only.")
        candidates = listings.head(6).to_dict("records")
    columns = st.columns(3)
    for index, candidate in enumerate(candidates):
        with columns[index % 3]:
            with st.container(border=True):
                st.caption(candidate["neighborhood"].upper())
                st.markdown(f"### {candidate['title']}")
                st.write(f"Up to {candidate['capacity']} guests")
                if "lodging_estimate" in candidate:
                    st.write(f"Lodging estimate: INR {candidate['lodging_estimate']:,.0f}")
                    st.caption("Fees and detailed eligibility require a quote.")
                else:
                    st.caption("Catalogue listing · availability not checked")
                quotes = [obs["result"] for obs in result.get("observations", []) if obs["tool"] == "quote_stay_option" and obs["result"].get("listing_id") == candidate["listing_id"]]
                for quote in quotes:
                    st.write(f"**{quote['status'].replace('_', ' ').title()}**")
                    st.caption(quote["reason"])
                    if "total" in quote:
                        st.metric("Total", f"INR {quote['total']:,.0f}")

# Operational charts aggregate each mart at its intended grain.
elif page == "Operations overview":
    st.subheader("A clear view of the portfolio")
    neighborhood = st.selectbox("Filter neighborhood", ["All", "Candolim", "Anjuna", "Panaji"])
    filtered = bookings if neighborhood == "All" else bookings[bookings.neighborhood == neighborhood]
    # Cancelled reservations contribute neither upcoming stays nor booked value.
    active = filtered[filtered.status != "cancelled"]
    upcoming = active[pd.to_datetime(active.check_in).dt.date >= date.fromisoformat(REFERENCE_DATE)]
    cols = st.columns(3)
    cols[0].metric("Reservations", f"{len(filtered):,}")
    cols[1].metric("Upcoming check-ins", f"{len(upcoming):,}")
    cols[2].metric("Booked lodging value", f"INR {active.booked_lodging_value.sum():,.0f}")
    st.caption("Dataset-wide booked value excludes cancelled reservations and fees; it is not recognized revenue.")
    monthly = active.assign(month=pd.to_datetime(active.check_in).dt.strftime("%Y-%m")).groupby("month").booked_lodging_value.sum()
    st.bar_chart(monthly, color="#147D80")
    if performance is not None:
        perf = performance if neighborhood == "All" else performance[performance.neighborhood == neighborhood]
        st.markdown("**Occupancy by month**")
        # Divide summed nights, rather than averaging listing-level percentages.
        occupancy = perf.groupby("month")[["occupied_nights", "offered_nights"]].sum()
        occupancy["Occupancy"] = occupancy.occupied_nights / occupancy.offered_nights.replace(0, float("nan"))
        st.line_chart(occupancy[["Occupancy"]], color="#DF6556")
    st.dataframe(upcoming[["booking_id", "title", "check_in", "check_out", "guest_count"]].head(25), hide_index=True, use_container_width=True)

# Execute verification inside the deployed app, using the same runtime and role.
else:
    from app.evaluation import run_checks

    st.subheader("Integration checks")
    st.write("Verify the deployed tools, then optionally test the live agent.")
    include_agent = st.checkbox("Include live Cortex agent checks (uses AI credits)", value=False)
    if st.button("Run checks", type="primary"):
        with st.spinner("Checking deployed Snowflake objects…"):
            checks = run_checks(get_session(), include_agent=include_agent)
        st.session_state.checks = checks
    if "checks" in st.session_state:
        checks = st.session_state.checks
        passed = sum(item["passed"] for item in checks)
        st.metric("Checks passed", f"{passed} / {len(checks)}")
        st.dataframe(pd.DataFrame(checks), hide_index=True, use_container_width=True)
        # Export verification results without writing to the application filesystem.
        st.download_button("Download check results", json.dumps(checks, indent=2, default=str),
                           "staywise-checks.json", "application/json")
