"""Two Snowflake procedures with deterministic availability and pricing rules.

This file is uploaded to CODE_STAGE unchanged. Handlers receive a Snowpark session.
Identifiers are fixed; guest-supplied values are always query parameters.
"""
from datetime import date, datetime, timezone
from decimal import Decimal


def parse_dates(check_in, check_out):
    """Parse and validate a stay window of one through thirty nights.

    Args:
        check_in (str | date): Inclusive start date in ISO date form.
        check_out (str | date): Exclusive checkout date in ISO date form.

    Returns:
        tuple[date, date]: Parsed start and end dates.

    Raises:
        ValueError: Either value is not an ISO date, checkout is not after check-in,
        or the requested stay exceeds thirty nights. Performs no database I/O.
    """
    start, end = date.fromisoformat(str(check_in)), date.fromisoformat(str(check_out))
    if not 1 <= (end - start).days <= 30:
        raise ValueError("Stay must contain 1-30 nights; checkout is exclusive")
    return start, end


def calculate_quote(listing, rule, days, check_in, check_out, guests, pet_type, mode):
    """Validate a complete nightly window and calculate an itemized INR quote.

    Args:
        listing (dict): Property record containing listing_id and capacity.
        rule (dict): Policy version with allowed_pet_types, minimum_nights,
            effective_from/effective_to, source_document_id, and per-stay fees.
        days (list[dict]): Calendar rows with stay_date, nightly_rate, host_blocked,
            and booking_count covering every requested night.
        check_in (str): Inclusive ISO start date.
        check_out (str): Exclusive ISO checkout date.
        guests (int): Positive guest count within the listing's capacity.
        pet_type (str): none, cat, or dog; normalized to lowercase.
        mode (str): new_stay applies per-stay fees; extension charges added nights.

    Returns:
        dict: Status/reason plus property, dates, policy provenance, and timestamp.
        Eligible results also contain nights, breakdown, and total. Other statuses
        are ineligible, unavailable, or needs_review; taxes_included is always false.

    Raises:
        ValueError: The dates are invalid, reversed, or exceed thirty nights.

    Notes:
        Does not query Snowflake or mutate inputs. Uses Decimal for fee arithmetic,
        then emits JSON-compatible numbers. The procedure caller must first verify
        an extension's booking identity, guest count, and original checkout date.
    """
    start, end = parse_dates(check_in, check_out)
    pet_type = pet_type.lower()
    # Carry rule provenance with every result, including rejected options.
    base = dict(listing_id=listing["listing_id"], check_in=str(start), check_out=str(end),
                guest_count=guests, pet_type=pet_type, mode=mode,
                source_document_id=rule["source_document_id"], rule_set_id=rule["rule_set_id"],
                quoted_at=datetime.now(timezone.utc).isoformat(), currency="INR", taxes_included=False)
    def reject(status, reason):
        """Attach an eligibility rejection to the current quote's provenance.

        Args:
            status (str): ineligible, unavailable, or needs_review.
            reason (str): Explanation of the failed business or completeness check.

        Returns:
            dict: A new dictionary combining the enclosing base quote metadata with
            status and reason. No price is attached and the base dictionary is unchanged.
        """
        return dict(base, status=status, reason=reason)
    # First check request validity, occupancy limits, and the exact pet species.
    if mode not in {"new_stay", "extension"}:
        return reject("needs_review", "Mode must be new_stay or extension")
    if not isinstance(guests, int) or isinstance(guests, bool) or not 1 <= guests <= int(listing["capacity"]):
        return reject("ineligible", "Guest count exceeds capacity or is invalid")
    if pet_type not in {"none", "cat", "dog"}:
        return reject("needs_review", "This application supports none, cat, or dog")
    if pet_type != "none" and pet_type not in rule["allowed_pet_types"].split(","):
        return reject("ineligible", "Pet species is not permitted by this listing's rule set")
    # Never apply a policy version outside its effective date interval.
    if start < date.fromisoformat(str(rule["effective_from"])) or end > date.fromisoformat(str(rule["effective_to"])):
        return reject("needs_review", "Rules do not cover the requested stay dates")
    # Checkout is exclusive: September 23-25 requires the nights of 23 and 24.
    expected = (end - start).days
    if mode == "new_stay" and expected < int(rule["minimum_nights"]):
        return reject("ineligible", "Minimum stay requirement is not met")
    # Count distinct dates as well as rows: duplicate dates cannot conceal gaps.
    actual_dates = [date.fromisoformat(str(day["stay_date"])) for day in days]
    if len(days) != expected or len(set(actual_dates)) != expected or any(not start <= d < end for d in actual_dates):
        return reject("needs_review", "Calendar is incomplete or contains duplicate dates")
    if any(day["nightly_rate"] is None for day in days):
        return reject("needs_review", "A nightly rate is missing")
    if any(bool(day["host_blocked"]) or int(day["booking_count"]) > 0 for day in days):
        return reject("unavailable", "At least one night is blocked or already booked")
    rates = [Decimal(str(day["nightly_rate"])) for day in days]
    if any(rate <= 0 for rate in rates):
        return reject("needs_review", "A nightly rate is invalid")
    # Extensions pay for added nights only; new stays incur the per-stay fees.
    lodging = sum(rates, Decimal("0"))
    cleaning = Decimal(str(rule["cleaning_fee"])) if mode == "new_stay" else Decimal("0")
    service = Decimal(str(rule["service_fee"])) if mode == "new_stay" else Decimal("0")
    pet = Decimal(str(rule["pet_fee"])) if mode == "new_stay" and pet_type != "none" else Decimal("0")
    if min(cleaning, service, pet) < 0:
        return reject("needs_review", "A fee is invalid")
    # Return ordinary numbers in VARIANT JSON, after decimal rounding to paise.
    amounts = {"lodging": lodging, "cleaning": cleaning, "service": service, "pet": pet}
    return dict(base, status="eligible", nights=expected,
                breakdown={k: float(v.quantize(Decimal("0.01"))) for k, v in amounts.items()},
                total=float(sum(amounts.values()).quantize(Decimal("0.01"))),
                reason="All requested nights and hard eligibility checks passed; not a reservation")


def rows(session, sql, params):
    """Execute a parameterized read and normalize Snowflake column names.

    Args:
        session (Session): Session provided to a Snowflake procedure handler.
        sql (str): Developer-defined SELECT statement with positional placeholders.
        params (list): Values bound to those placeholders in matching order.

    Returns:
        list[dict]: Collected rows with lowercase column keys; an empty list when
        the query finds no matching records.

    Raises:
        SnowparkSQLException: Snowflake cannot execute the supplied query.

    Notes:
        Executes synchronously. Identifiers must remain fixed in caller code;
        pass guest-supplied values only through params.
    """
    return [{k.lower(): v for k, v in r.as_dict().items()} for r in session.sql(sql, params=params).collect()]


def find_available_stays(session, check_in, check_out, neighborhood, guests, pet_type, max_total):
    """Find fully available properties using coarse capacity, pet, and price filters.

    Args:
        session (Session): Snowpark session injected by the procedure runtime.
        check_in (str): Inclusive ISO start date.
        check_out (str): Exclusive ISO checkout date.
        neighborhood (str): Exact neighborhood match.
        guests (int): Positive required guest capacity.
        pet_type (str): none, cat, or dog.
        max_total (float): Positive INR budget used to filter lodging-only estimates.

    Returns:
        dict: candidates (at most five, ordered by lodging estimate and listing ID)
        plus an explanation that fees and exact pet eligibility need a quote.

    Raises:
        ValueError: Invalid dates, nonpositive guests/budget, or unsupported pet type.
        SnowparkSQLException: The candidate-query execution fails.

    Notes:
        Requires every requested night to exist, have a positive rate, and be free
        of host blocks and bookings. The broad pets_allowed flag does not approve
        a species; candidates may still fail quote_stay_option.
    """
    start, end = parse_dates(check_in, check_out)
    if guests < 1 or max_total <= 0 or pet_type not in {"none", "cat", "dog"}:
        raise ValueError("Supply positive guests/budget and pet_type none, cat, or dog")
    # Keep every requested date in the group. HAVING then rejects gaps, blocked
    # nights, and overlapping bookings instead of summing only available nights.
    # The broad pet flag deliberately leaves species validation to the quote.
    candidates = rows(session, """
        SELECT l.listing_id, l.title, l.neighborhood, l.capacity, l.rule_set_id,
               SUM(d.nightly_rate) AS lodging_estimate
        FROM STAYWISE_DB.ANALYTICS.DIM_LISTING l
        JOIN STAYWISE_DB.ANALYTICS.MART_LISTING_DAY d USING (listing_id)
        WHERE d.stay_date >= TO_DATE(?) AND d.stay_date < TO_DATE(?)
          AND l.neighborhood = ? AND l.capacity >= ?
          AND (? = 'none' OR l.pets_allowed)
        GROUP BY l.listing_id, l.title, l.neighborhood, l.capacity, l.rule_set_id
        HAVING COUNT(*) = ? AND COUNT(d.nightly_rate) = ?
           AND COUNT_IF(d.host_blocked OR d.booking_count > 0) = 0
           AND MIN(d.nightly_rate) > 0 AND SUM(d.nightly_rate) <= ?
        ORDER BY lodging_estimate, l.listing_id LIMIT 5
    """, [str(start), str(end), neighborhood, guests, pet_type, (end-start).days, (end-start).days, max_total])
    return {"candidates": [{**r, "lodging_estimate": float(r["lodging_estimate"])} for r in candidates],
            "note": "Coarse pet flag and lodging-only estimate. Retrieve rules and call quote_stay_option before recommending."}


def quote_stay_option(session, listing_id, check_in, check_out, guests, pet_type, mode, booking_id):
    """Load authoritative records and quote a new stay or booking extension.

    Args:
        session (Session): Snowpark session injected by Snowflake.
        listing_id (str): Property to evaluate.
        check_in (str): Inclusive ISO date for the requested nights.
        check_out (str): Exclusive ISO checkout date.
        guests (int): Number of guests requesting the stay.
        pet_type (str): none, cat, or dog.
        mode (str): new_stay or extension.
        booking_id (str): Confirmed original booking for extension; unused for new_stay.

    Returns:
        dict: An itemized eligible quote or a status/reason explaining rejection.
        Unknown properties, invalid extension context, and missing policy versions
        return needs_review before pricing.

    Raises:
        ValueError: Requested dates are invalid or outside the supported duration.
        SnowparkSQLException: A listing, booking, policy, or calendar read fails.

    Notes:
        Extensions must match the original listing, guest count, and checkout,
        and retain the booking's policy version. The nightly window is passed to
        calculate_quote for hard checks and pricing. No reservation is modified.
    """
    start, end = parse_dates(check_in, check_out)
    # Fixed object names and bound values keep caller inputs out of SQL syntax.
    listings = rows(session, "SELECT * FROM STAYWISE_DB.ANALYTICS.DIM_LISTING WHERE listing_id = ?", [listing_id])
    if not listings:
        return {"status": "needs_review", "reason": "Unknown listing"}
    listing = listings[0]
    rule_id = listing["rule_set_id"]
    # Extensions retain the original booking's policy version and must start
    # exactly at its checkout; this prevents quoting an unrelated reservation.
    if mode == "extension":
        bookings = rows(session, "SELECT * FROM STAYWISE_DB.ANALYTICS.FCT_BOOKING WHERE booking_id = ?", [booking_id])
        if not bookings or bookings[0]["status"] != "confirmed":
            return {"status": "needs_review", "reason": "Extension requires a confirmed booking"}
        booking = bookings[0]
        if booking["listing_id"] != listing_id or str(booking["check_out"]) != str(start) or int(booking["guest_count"]) != guests:
            return {"status": "needs_review", "reason": "Extension must match listing, guest count, and original checkout"}
        rule_id = booking["rule_set_id"]
    # A missing or ambiguous rule is incomplete evidence, never automatic approval.
    rules = rows(session, "SELECT * FROM STAYWISE_DB.ANALYTICS.POLICY_RULES WHERE rule_set_id = ?", [rule_id])
    if len(rules) != 1:
        return {"status": "needs_review", "reason": "Missing or ambiguous policy version"}
    # Read a complete nightly window, then let the pure function price/check it.
    days = rows(session, """SELECT stay_date, nightly_rate, host_blocked, booking_count
        FROM STAYWISE_DB.ANALYTICS.MART_LISTING_DAY
        WHERE listing_id = ? AND stay_date >= TO_DATE(?) AND stay_date < TO_DATE(?)
        ORDER BY stay_date""", [listing_id, str(start), str(end)])
    return calculate_quote(listing, rules[0], days, str(start), str(end), guests, pet_type, mode)
