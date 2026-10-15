"""Non-secret configuration for the Streamlit warehouse runtime in Snowflake.

Edit MODEL in the Snowsight app editor if the preflight selects another model.
Authentication comes from the active Snowflake session; no credentials or
environment variables are needed by this application.
"""

# Fully qualified names keep tools independent of the current session schema.
DATABASE = "STAYWISE_DB"
SEMANTIC_VIEW = f"{DATABASE}.AI.STAY_ANALYTICS"
SEARCH_SERVICE = f"{DATABASE}.KNOWLEDGE.STAY_SEARCH"

# This is the planning LLM. Cortex Analyst chooses its own text-to-SQL model.
MODEL = "claude-sonnet-4-6"

# Frozen dates make the supplied bookings and expected results reproducible.
REFERENCE_DATE = "2026-09-18"

# Bound the number of tools one investigation can invoke.
MAX_TOOL_CALLS = 8
