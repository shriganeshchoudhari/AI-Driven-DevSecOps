import json
import logging
import os
from typing import Any, Dict, List, Optional

from langchain.callbacks import get_openai_callback
from langchain.chains import LLMChain
from langchain.prompts import PromptTemplate

from src.config import settings
from src.models.schemas import Incident, RCAResult
from src.services.vectorstore import VectorStoreService

logger = logging.getLogger(__name__)


class LLMService:
    def __init__(self, vectorstore: VectorStoreService):
        self.vectorstore = vectorstore
        self.llm = None
        self._initialize_llm()

        def _load_prompt(self, filename: str) -> str:
            base = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "prompts"))
            path = os.path.join(base, filename)
            with open(path, "r", encoding="utf-8") as f:
                return f.read()

        self.rca_prompt = PromptTemplate(
            input_variables=[
                "incident_title",
                "incident_description",
                "events",
                "alerts",
                "similar_incidents",
            ],
            template=self._load_prompt("rca_prompt.txt"),
        )

        self.summary_prompt = PromptTemplate(
            input_variables=["incidents"],
            template="""Summarize the following production incidents in a concise format suitable for an executive report.
            
Incidents: {incidents}

Provide:
1. Overall status summary (1 sentence)
2. Key incidents requiring attention (max 3)
3. Trends or patterns observed
4. Recommended actions""",
        )

        self.threat_intel_prompt = PromptTemplate(
            input_variables=["alerts"],
            template="""Analyze these security alerts and provide threat intelligence assessment:
            
Alerts: {alerts}

Provide:
1. Overall threat level assessment
2. Most critical findings
3. MITRE ATT&CK techniques observed
4. Recommended containment actions
5. Recommended remediation steps""",
        )

    def _initialize_llm(self):
        if settings.LLM_PROVIDER == "openai" and settings.OPENAI_API_KEY:
            from langchain.llms import OpenAI

            self.llm = OpenAI(
                model=settings.OPENAI_MODEL,
                temperature=settings.TEMPERATURE,
                max_tokens=settings.MAX_TOKENS,
                api_key=settings.OPENAI_API_KEY,
            )
            logger.info(f"Initialized OpenAI LLM: {settings.OPENAI_MODEL}")
        else:
            try:
                from langchain.llms import Ollama

                self.llm = Ollama(
                    model=settings.OLLAMA_MODEL,
                    base_url=settings.OLLAMA_BASE_URL,
                    temperature=settings.TEMPERATURE,
                )
                logger.info(f"Initialized Ollama LLM: {settings.OLLAMA_MODEL}")
            except Exception as e:
                logger.warning(f"Failed to initialize Ollama, falling back to mock: {e}")
                self.llm = None

    async def generate_rca(self, incident: Incident) -> RCAResult:
        if not self.llm:
            return await self._mock_rca(incident)

        similar = await self.vectorstore.search_similar_incidents(incident)

        events_str = (
            "\n".join(
                [json.dumps(e, indent=2)[:500] for e in incident.events[-10:]]
            )
            if incident.events
            else "No events recorded"
        )

        alerts_str = (
            "\n".join(
                [json.dumps(a, indent=2)[:500] for a in incident.alerts[-5:]]
            )
            if incident.alerts
            else "No alerts recorded"
        )

        similar_str = (
            json.dumps(similar[:3], indent=2)
            if similar
            else "No similar incidents found"
        )

        chain = LLMChain(llm=self.llm, prompt=self.rca_prompt)

        with get_openai_callback() as cb:
            result = await chain.arun(
                incident_title=incident.title,
                incident_description=incident.description,
                events=events_str,
                alerts=alerts_str,
                similar_incidents=similar_str,
            )
            logger.info(f"RCA generated. Tokens used: {cb.total_tokens}")

        try:
            result_json = json.loads(result)
            return RCAResult(
                incident_id=incident.id or "unknown",
                root_cause=result_json.get("root_cause", "Analysis incomplete"),
                confidence=result_json.get("confidence", 0.5),
                contributing_factors=result_json.get("contributing_factors", []),
                timeline=result_json.get("timeline", []),
                affected_services=result_json.get("affected_services", []),
                recommendations=result_json.get("recommendations", []),
                similar_incidents=similar[:3],
            )
        except json.JSONDecodeError:
            return RCAResult(
                incident_id=incident.id or "unknown",
                root_cause=result[:500],
                confidence=0.5,
                contributing_factors=[],
                timeline=[],
                affected_services=[],
                recommendations=[],
                similar_incidents=similar[:3],
            )

    async def summarize(self, incidents: List[Incident]) -> str:
        if not self.llm:
            return self._mock_summary(incidents)

        incidents_str = json.dumps(
            [
                {
                    "title": i.title,
                    "severity": i.severity,
                    "status": i.status,
                    "description": i.description[:200],
                }
                for i in incidents[:10]
            ],
            indent=2,
        )

        chain = LLMChain(llm=self.llm, prompt=self.summary_prompt)
        return await chain.arun(incidents=incidents_str)

    async def analyze_threats(self, alerts: List[Dict[str, Any]]) -> str:
        if not self.llm:
            return self._mock_threat_analysis(alerts)

        alerts_str = json.dumps(alerts[:10], indent=2)
        chain = LLMChain(llm=self.llm, prompt=self.threat_intel_prompt)
        return await chain.arun(alerts=alerts_str)

    async def _mock_rca(self, incident: Incident) -> RCAResult:
        similar = await self.vectorstore.search_similar_incidents(incident)
        return RCAResult(
            incident_id=incident.id or "unknown",
            root_cause=f"Analysis based on {len(incident.events)} events and {len(incident.alerts)} alerts. "
            f"Primary indicator: {incident.description[:100]}.",
            confidence=0.6,
            contributing_factors=[
                "Increased error rate detected in service logs",
                "Resource exhaustion pattern observed",
            ],
            timeline=[
                {"time": "T-30min", "event": "Initial error spike detected"},
                {"time": "T-15min", "event": "Alert triggered"},
                {"time": "T-0min", "event": "Incident created"},
            ],
            affected_services=[incident.service] if incident.service else ["unknown"],
            recommendations=[
                "Investigate recent deployments",
                "Check resource utilization metrics",
                "Review application logs for error patterns",
            ],
            similar_incidents=similar,
        )

    def _mock_summary(self, incidents: List[Incident]) -> str:
        total = len(incidents)
        critical = sum(1 for i in incidents if i.severity == "critical")
        open_inc = sum(1 for i in incidents if i.status not in ("resolved", "closed"))
        return (
            f"Summary: {total} incidents analyzed, {critical} critical, "
            f"{open_inc} currently open. Recommended actions: "
            f"prioritize critical severity incidents for immediate RCA."
        )

    def _mock_threat_analysis(self, alerts: List[Dict[str, Any]]) -> str:
        priorities = [a.get("priority", "unknown") for a in alerts]
        return (
            f"Threat assessment: {len(alerts)} alerts analyzed. "
            f"Priorities observed: {set(priorities)}. "
            f"Recommended: isolate affected resources and investigate immediately."
        )
