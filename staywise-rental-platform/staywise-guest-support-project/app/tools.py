"""Four readable adapters bridge the ReAct loop to Snowflake services."""
import json
import time
from jsonschema import validate

from app.settings import SEMANTIC_VIEW
from app.sql_guard import validate_sql


def object_schema(properties, required):
    """Create a JSON Schema object used to validate a tool's arguments.

    Args:
        properties (dict): Argument names mapped to their JSON Schema definitions.
        required (list[str]): Argument names that must be present.

    Returns:
        dict: Object schema with additionalProperties disabled, so the model
        cannot add undeclared tool inputs. No external calls are made.
    """
    return {"type": "object", "properties": properties, "required": required, "additionalProperties": False}


TEXT = {"type": "string"}
# Descriptions tell the LLM when to choose each tool. The methods below perform
# the actions; the model cannot invent additional methods or input fields.
TOOLS = {
    "query_stay_data": {
        "description": "Read an existing reservation or booking statistics via Cortex Analyst and validated SQL. Use for B-1042 context before extending it.",
        "parameters": object_schema({"question": TEXT}, ["question"]),
    },
    "search_stay_documents": {
        "description": "Retrieve house rules and source citations for specified listing IDs. Use GLOBAL for the general support guide. Verify pet species, not just pets_allowed.",
        "parameters": object_schema({"query": TEXT, "listing_ids": {"type": "array", "items": TEXT, "minItems": 1, "maxItems": 5}}, ["query", "listing_ids"]),
    },
    "find_available_stays": {
        "description": "Find up to five coarse candidates. Rates exclude fees and pet flags are broad; search documents and obtain a quote before recommending.",
        "parameters": object_schema({"check_in": TEXT, "check_out": TEXT, "neighborhood": TEXT,
            "guests": {"type": "integer", "minimum": 1}, "pet_type": {"type": "string", "enum": ["none", "cat", "dog"]},
            "max_total": {"type": "number", "exclusiveMinimum": 0}},
            ["check_in", "check_out", "neighborhood", "guests", "pet_type", "max_total"]),
    },
    "quote_stay_option": {
        "description": "Check all dates and hard rules, then calculate the full price. extension requires the original booking ID; new_stay uses an empty booking_id.",
        "parameters": object_schema({"listing_id": TEXT, "check_in": TEXT, "check_out": TEXT,
            "guests": {"type": "integer", "minimum": 1}, "pet_type": {"type": "string", "enum": ["none", "cat", "dog"]},
            "mode": {"type": "string", "enum": ["extension", "new_stay"]}, "booking_id": TEXT},
            ["listing_id", "check_in", "check_out", "guests", "pet_type", "mode", "booking_id"]),
    },
}


def json_value(value):
    """Normalize a Snowpark VARIANT result into its Python representation.

    Args:
        value: A JSON string or an already-decoded Snowpark result.

    Returns:
        object: Decoded JSON for strings; the original value for all other types.

    Raises:
        json.JSONDecodeError: A string value is not valid JSON.
    """
    return json.loads(value) if isinstance(value, str) else value


def post_api(path, payload):
    """Call an in-account Cortex endpoint through the Snowflake runtime bridge.

    Args:
        path (str): Relative Snowflake API path for Analyst or Cortex Search.
        payload (dict): JSON request body expected by the selected endpoint.

    Returns:
        dict: Decoded JSON response from a successful API call.

    Raises:
        RuntimeError: Snowflake returns an HTTP error after any allowed retry.
        json.JSONDecodeError: A successful response does not contain valid JSON.

    Notes:
        The warehouse runtime supplies authentication through _snowflake. The
        request timeout is 60 seconds. HTTP 429/500/502/503/504 receive one retry
        after one second; other errors fail immediately. Response bodies are not
        included in error messages. Runtime bridge exceptions propagate unchanged.
    """
    import _snowflake

    for attempt in range(2):
        # Arguments: method, API path, headers, query parameters, JSON body,
        # request identifier, and timeout in milliseconds. Snowflake adds auth.
        response = _snowflake.send_snow_api_request(
            "POST", path, {}, {}, payload, None, 60000
        )
        status = response["status"]
        # Retry transient service failures once; permanent errors need attention.
        if status in {429, 500, 502, 503, 504} and attempt == 0:
            time.sleep(1)
            continue
        if status >= 400:
            raise RuntimeError(f"Snowflake API returned HTTP {status}; check role, service, and Cortex availability in the runbook")
        return json.loads(response["content"])
    raise RuntimeError("Snowflake API retry budget exhausted")


class SnowflakeTools:
    """Use one active Snowpark session for all tools in an investigation."""

    def __init__(self, session):
        # Share Snowflake's existing session; do not open a second connection.
        """Bind the active session used to execute reads and stored procedures.

        Args:
            session (Session): Snowpark session running with the application role.

        Returns:
            None. Retains the supplied session without opening another connection.
        """
        self.session = session

    def call(self, name, arguments):
        """Validate and dispatch one model-selected tool invocation.

        Args:
            name (str): One of the registered names in TOOLS.
            arguments (dict): Named inputs matching that tool's parameters schema.

        Returns:
            dict: Result from the matching query, search, candidate, or quote adapter.

        Raises:
            ValueError: The requested tool name is not registered.
            jsonschema.ValidationError: Required inputs, types, or value limits fail.

        Notes:
            Adapter errors propagate to run_agent, which records them as observations.
            getattr is used only after the name has passed the explicit tool allowlist.
        """
        if name not in TOOLS:
            raise ValueError("Unknown tool")
        validate(arguments, TOOLS[name]["parameters"])
        return getattr(self, name)(**arguments)

    def query_stay_data(self, question):
        """Generate and execute an approved analytical query with Cortex Analyst.

        Args:
            question (str): Natural-language question about bookings or booking metrics.

        Returns:
            dict: rows (at most 100), executed sql, and query_ids; or a
            clarification_needed status with Analyst content when no SQL was returned.

        Raises:
            ValueError: Analyst SQL violates the table/function/query-shape policy.
            RuntimeError: The Analyst API request fails.
            SnowparkSQLException: An approved SQL query fails during execution.

        Notes:
            Makes a model-backed Analyst call and then, if present, executes its first
            SQL statement only after AST validation. Returned column keys are lowercase.
        """
        # Ordinary base-table SQL is intentional: the guard is small and auditable.
        instruction = ("Use ordinary SELECT SQL over STAYWISE_DB.ANALYTICS.MART_BOOKING_CONTEXT, "
                       "not the SEMANTIC_VIEW table function. Fully qualify the table. "
                       "The fixed reference date is 2026-09-18. Question: ")
        result = post_api("/api/v2/cortex/analyst/message", {
            "semantic_view": SEMANTIC_VIEW,
            "messages": [{"role": "user", "content": [{"type": "text", "text": instruction + question}]}],
            "stream": False,
        })
        # Analyst can ask a clarification instead of returning executable SQL.
        blocks = result.get("message", {}).get("content", [])
        statements = [block["statement"] for block in blocks if block.get("type") == "sql"]
        if not statements:
            return {"status": "clarification_needed", "analyst_response": blocks}
        # Treat generated SQL as untrusted until the table/function guard passes.
        sql = validate_sql(statements[0])
        frame = self.session.sql(sql)
        # Preserve query IDs so developers can inspect the actual warehouse query.
        with self.session.query_history() as history:
            records = frame.collect()
        return {"rows": [{key.lower(): value for key, value in row.as_dict().items()} for row in records],
                "sql": sql, "query_ids": [query.query_id for query in history.queries]}

    def search_stay_documents(self, query, listing_ids):
        """Retrieve policy passages filtered to the requested property identifiers.

        Args:
            query (str): Search question about house rules or support policy.
            listing_ids (list[str]): Property IDs to search; GLOBAL selects the shared
                support guide. The tool schema limits this list to one through five IDs.

        Returns:
            dict: passages with normalized keys and citation metadata, plus request_id.
            An empty passages list means no matching evidence was returned.

        Raises:
            RuntimeError: The Cortex Search endpoint rejects or fails the request.

        Notes:
            Requests at most eight results and preserves document, page, rule version,
            and effective-date fields. Retrieval does not establish quote eligibility.
        """
        # Unquoted Snowflake SQL columns are uppercase; normalize API results at the boundary.
        scope = {"@or": [{"@eq": {"LISTING_ID": value}} for value in listing_ids]}
        result = post_api(
            "/api/v2/databases/STAYWISE_DB/schemas/KNOWLEDGE/cortex-search-services/STAY_SEARCH:query", {
                "query": query, "filter": scope, "limit": 8,
                "columns": ["CHUNK_ID", "DOC_ID", "TITLE", "LISTING_ID", "RULE_SET_ID", "CHUNK_TEXT",
                            "PAGE_NUMBER", "RELATIVE_PATH", "EFFECTIVE_FROM", "EFFECTIVE_TO"],
            })
        passages = [{key.lower(): value for key, value in row.items()} for row in result.get("results", [])]
        return {"passages": passages, "request_id": result.get("request_id")}

    def find_available_stays(self, check_in, check_out, neighborhood, guests, pet_type, max_total):
        """Invoke the deployed candidate-search procedure for a constrained stay.

        Args:
            check_in (str): Inclusive ISO date, YYYY-MM-DD.
            check_out (str): Exclusive ISO date, YYYY-MM-DD.
            neighborhood (str): Exact neighborhood name to search.
            guests (int): Required guest capacity.
            pet_type (str): none, cat, or dog.
            max_total (float): Upper budget in INR, used here to filter lodging estimates.

        Returns:
            dict: Up to five candidates and a note requiring a full quote before use.

        Raises:
            SnowparkSQLException: The procedure rejects inputs or its execution fails.

        Notes:
            Passes values as procedure arguments. Detailed species rules and fees are
            checked by quote_stay_option, not by this candidate adapter.
        """
        value = self.session.call("STAYWISE_DB.AI.FIND_AVAILABLE_STAYS", check_in, check_out, neighborhood, guests, pet_type, float(max_total))
        return json_value(value)

    def quote_stay_option(self, listing_id, check_in, check_out, guests, pet_type, mode, booking_id):
        """Invoke the deployed procedure that checks eligibility and calculates fees.

        Args:
            listing_id (str): Property to quote.
            check_in (str): Inclusive ISO start date.
            check_out (str): Exclusive ISO checkout date.
            guests (int): Number of guests.
            pet_type (str): none, cat, or dog.
            mode (str): new_stay or extension.
            booking_id (str): Original booking ID for extension; empty for new_stay.

        Returns:
            dict: Procedure result with an eligibility status and reason. Eligible
            results include itemized INR amounts and policy provenance.

        Raises:
            SnowparkSQLException: Procedure validation or execution fails.

        Notes:
            Calls the Snowflake procedure through the active Snowpark session.
            No inventory is reserved, and returned amounts exclude taxes.
        """
        value = self.session.call("STAYWISE_DB.AI.QUOTE_STAY_OPTION", listing_id, check_in, check_out, guests, pet_type, mode, booking_id)
        return json_value(value)
