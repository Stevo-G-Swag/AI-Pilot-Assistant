from uuid import uuid4

from pydantic import BaseModel, Field

from core.agents.base import BaseAgent
from core.agents.convo import AgentConvo
from core.agents.response import AgentResponse
from core.config import TECH_LEAD_PLANNING
from core.db.models.project_state import TaskStatus
from core.llm.parser import JSONParser
from core.log import get_logger
from core.telemetry import telemetry
from core.templates.example_project import EXAMPLE_PROJECTS
from core.templates.registry import PROJECT_TEMPLATES
from core.ui.base import ProjectStage, success_source

log = get_logger(__name__)


class Epic(BaseModel):
    description: str = Field(description="Description of an epic.")


class Task(BaseModel):
    description: str = Field(description="Description of a task.")
    solution: str = Field(description="Proposed solution for the task.")
    review: str = Field(description="Review of the proposed solution.")


class DevelopmentPlan(BaseModel):
    plan: list[Epic] = Field(description="List of epics that need to be done to implement the entire plan.")


class EpicPlan(BaseModel):
    plan: list[Task] = Field(description="List of tasks that need to be done to implement the entire epic.")


class UpdatedDevelopmentPlan(BaseModel):
    updated_current_epic: Epic = Field(
        description="Updated description of what was implemented while working on the current epic."
    )
    plan: list[Task] = Field(description="List of unfinished epics.")


class TechLead(BaseAgent):
    agent_type = "tech-lead"
    display_name = "Tech Lead"

    async def run(self) -> AgentResponse:
        if self.current_state.tasks:
            return await self.update_epic()
        else:
            return await self.plan_project()

    async def plan_project(self) -> AgentResponse:
        await self.send_message("Planning the project and creating development plan...")

        llm = self.get_llm(stream_output=True)
        convo = AgentConvo(self).template(
            "create_plan",
            project_description=self.current_state.specification.description,
        )
        llm_response = await llm(convo, parser=JSONParser(DevelopmentPlan))

        self.next_state.epics = [
            {
                "id": uuid4().hex,
                "name": epic.description,
                "description": epic.description,
                "completed": False,
                "tasks": [],
                "complexity": self.current_state.specification.complexity,
            }
            for epic in llm_response.plan
        ]

        await self.break_down_epics()

        self.next_state.action = "Project plan created"
        return AgentResponse.done(self)

    async def break_down_epics(self):
        for epic in self.next_state.epics:
            llm = self.get_llm(stream_output=True)
            convo = AgentConvo(self).template(
                "break_down_epic",
                epic_description=epic["description"],
            )
            llm_response = await llm(convo, parser=JSONParser(EpicPlan))

            epic["tasks"] = [
                {
                    "id": uuid4().hex,
                    "description": task.description,
                    "solution": task.solution,
                    "review": task.review,
                    "status": TaskStatus.TODO,
                }
                for task in llm_response.plan
            ]

    async def update_epic(self) -> AgentResponse:
        epic = self.current_state.current_epic
        finished_tasks = self.current_state.tasks
        llm = self.get_llm()
        convo = AgentConvo(self).template(
            "update_plan",
            epic=epic,
            modified_files=self.current_state.modified_file_objects,
        )
        llm_response = await llm(convo, parser=JSONParser(UpdatedDevelopmentPlan))

        # Update the development plan
        self.next_state.epics[-1]["description"] = llm_response.updated_current_epic.description
        self.next_state.tasks = [
            {
                "id": uuid4().hex,
                "description": task.description,
                "instructions": None,
                "status": TaskStatus.TODO,
            }
            for task in llm_response.plan
        ]
        self.next_state.action = "Development plan updated"
        return AgentResponse.done(self)

    def plan_example_project(self):
        example_name = self.current_state.specification.example_project
        log.debug(f"Planning example project: {example_name}")

        example = EXAMPLE_PROJECTS[example_name]
        self.next_state.epics = [
            {
                "name": "Initial Project",
                "description": example["description"],
                "completed": False,
                "complexity": example["complexity"],
            }
        ]
        self.next_state.tasks = example["plan"]
