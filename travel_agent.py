import logging
import os

import uvicorn
from crewai import Agent, Task
from crewai.a2a import A2AServerConfig
from crewai.a2a.utils.task import execute as crewai_a2a_execute

from a2a.server.agent_execution import AgentExecutor, RequestContext
from a2a.server.apps import A2AStarletteApplication
from a2a.server.events import EventQueue
from a2a.server.request_handlers import DefaultRequestHandler
from a2a.server.tasks import InMemoryTaskStore

logger = logging.getLogger(__name__)

# Configuration via environment variables
# Local dev defaults to ollama; Cloud Run overrides via Terraform (see infra/variables.tf)
try:
    PORT = int(os.getenv("PORT", "8001"))
except ValueError:
    raise SystemExit(f"PORT must be an integer, got: {os.getenv('PORT')!r}")
AGENT_URL = os.getenv("AGENT_URL", f"http://localhost:{PORT}")
LLM_MODEL = os.getenv("LLM_MODEL", "ollama/llama3.1:8b")

# --- 1. Define the CrewAI Agent ---
travel_agent = Agent(
    role="Senior Travel Consultant",
    goal="Design luxury itineraries and find flight/hotel options",
    backstory="Expert with 15 years in travel planning, specialized in hidden gems.",
    llm=LLM_MODEL,
    a2a=A2AServerConfig(
        url=AGENT_URL,
        name="GlobalTravelBot",
        description="A specialized agent for travel research and booking.",
    ),
)

itinerary_task = Task(
    description="Research a 3-day trip to Tokyo with a focus on food.",
    expected_output="A Markdown table with daily activities and estimated costs.",
    agent=travel_agent,
)


# --- 2. Bridge CrewAI agent to A2A SDK's AgentExecutor interface ---
class CrewAIAgentExecutor(AgentExecutor):
    def __init__(self, agent: Agent):
        self.agent = agent

    async def execute(self, context: RequestContext, event_queue: EventQueue) -> None:
        try:
            await crewai_a2a_execute(self.agent, context, event_queue)
        except Exception:
            logger.exception("Agent execution failed")
            raise

    async def cancel(self, context: RequestContext, event_queue: EventQueue) -> None:
        logger.warning("Cancel requested but not supported")


# --- 3. Build and run the A2A server ---
if __name__ == "__main__":
    agent_card = travel_agent.to_agent_card(AGENT_URL)

    agent_executor = CrewAIAgentExecutor(travel_agent)
    request_handler = DefaultRequestHandler(
        agent_executor=agent_executor,
        task_store=InMemoryTaskStore(),
    )
    a2a_app = A2AStarletteApplication(
        agent_card=agent_card,
        http_handler=request_handler,
    )
    app = a2a_app.build()

    logging.basicConfig(level=logging.INFO)
    logger.info("Travel Agent is live on the A2A Protocol at %s", AGENT_URL)
    logger.info("  Agent card: %s/.well-known/agent-card.json", AGENT_URL)
    logger.info("  JSON-RPC:   %s/", AGENT_URL)
    uvicorn.run(app, host="0.0.0.0", port=PORT)
