import re
from difflib import unified_diff
from enum import Enum

from pydantic import BaseModel, Field

from core.agents.base import BaseAgent
from core.agents.convo import AgentConvo
from core.agents.response import AgentResponse
from core.llm.parser import JSONParser
from core.log import get_logger

log = get_logger(__name__)


# Constant for indicating missing new line at the end of a file in a unified diff
NO_EOL = "\\ No newline at end of file"

# Regular expression pattern for matching hunk headers
PATCH_HEADER_PATTERN = re.compile(r"^@@ -(\d+),?(\d+)? \+(\d+),?(\d+)? @@")

# Maximum number of attempts to ask for review if it can't be parsed
MAX_REVIEW_RETRIES = 2

# Maximum number of code implementation attempts after which we accept the changes unconditionaly
MAX_CODING_ATTEMPTS = 3


class Decision(str, Enum):
    APPLY = "apply"
    IGNORE = "ignore"
    REWORK = "rework"


class Hunk(BaseModel):
    number: int = Field(description="Index of the hunk in the diff. Starts from 1.")
    reason: str = Field(description="Reason for applying or ignoring this hunk, or for asking for it to be reworked.")
    decision: Decision = Field(description="Whether to apply this hunk, rework, or ignore it.")


class ReviewChanges(BaseModel):
    hunks: list[Hunk]
    review_notes: str = Field(description="Additional review notes (optional, can be empty).")


class CodeReviewer(BaseAgent):
    agent_type = "code-reviewer"
    display_name = "Code Reviewer"

    async def run(self) -> AgentResponse:
        if (
            not self.prev_response.data["old_content"]
            or self.prev_response.data["new_content"] == self.prev_response.data["old_content"]
            or self.prev_response.data["attempt"] >= MAX_CODING_ATTEMPTS
        ):
            return await self.accept_changes(self.prev_response.data["path"], self.prev_response.data["new_content"])

        approved_content, feedback = await self.review_change(
            self.prev_response.data["path"],
            self.prev_response.data["instructions"],
            self.prev_response.data["old_content"],
            self.prev_response.data["new_content"],
        )
        if feedback:
            return AgentResponse.code_review_feedback(
                self,
                new_content=self.prev_response.data["new_content"],
                approved_content=approved_content,
                feedback=feedback,
                attempt=self.prev_response.data["attempt"],
            )
        else:
            return await self.accept_changes(self.prev_response.data["path"], approved_content)

    async def accept_changes(self, path: str, content: str) -> AgentResponse:
        await self.state_manager.save_file(path, content)
        self.next_state.complete_step()

        input_required = self.state_manager.get_input_required(content)
        if input_required:
            return AgentResponse.input_required(
                self,
                [{"file": path, "line": line} for line in input_required],
            )
        else:
            return AgentResponse.done(self)

    def _get_task_convo(self) -> AgentConvo:
        task = self.current_state.current_task
        current_task_index = self.current_state.tasks.index(task)

        convo = AgentConvo(self).template(
            "breakdown",
            task=task,
            iteration=None,
            current_task_index=current_task_index,
        )
        if self.current_state.iterations:
            convo.assistant(self.current_state.iterations[-1]["description"])
        else:
            convo.assistant(self.current_state.current_task["instructions"])
        return convo

    async def review_change(
        self, file_name: str, instructions: str, old_content: str, new_content: str
    ) -> tuple[str, str]:
        hunks = self.get_diff_hunks(file_name, old_content, new_content)

        llm = self.get_llm()
        convo = (
            self._get_task_convo()
            .template(
                "review_changes",
                instructions=instructions,
                file_name=file_name,
                old_content=old_content,
                hunks=hunks,
            )
            .require_schema(ReviewChanges)
        )
        llm_response: ReviewChanges = await llm(convo, temperature=0, parser=JSONParser(ReviewChanges))

        for i in range(MAX_REVIEW_RETRIES):
            reasons = {}
            ids_to_apply = set()
            ids_to_ignore = set()
            ids_to_rework = set()
            for hunk in llm_response.hunks:
                reasons[hunk.number - 1] = hunk.reason
                if hunk.decision == "apply":
                    ids_to_apply.add(hunk.number - 1)
                elif hunk.decision == "ignore":
                    ids_to_ignore.add(hunk.number - 1)
                elif hunk.decision == "rework":
                    ids_to_rework.add(hunk.number - 1)

            n_hunks = len(hunks)
            n_review_hunks = len(reasons)
            if n_review_hunks == n_hunks:
                break
            elif n_review_hunks < n_hunks:
                error = "Not all hunks have been reviewed. Please review all hunks and add 'apply', 'ignore' or 'rework' decision for each."
            elif n_review_hunks > n_hunks:
                error = f"Your review contains more hunks ({n_review_hunks}) than in the original diff ({n_hunks}). Note that one hunk may have multiple changed lines."

            convo.assistant(llm_response.model_dump_json()).user(error)
            llm_response = await llm(convo, parser=JSONParser(ReviewChanges))
        else:
            return new_content, None

        hunks_to_apply = [h for i, h in enumerate(hunks) if i in ids_to_apply]
        diff_log = f"--- {file_name}\n+++ {file_name}\n" + "\n".join(hunks_to_apply)

        hunks_to_rework = [(i, h) for i, h in enumerate(hunks) if i in ids_to_rework]
        review_log = (
            "\n\n".join([f"## Change\n```{hunk}```\nReviewer feedback:\n{reasons[i]}" for (i, hunk) in hunks_to_rework])
            + "\n\nReview notes:\n"
            + llm_response.review_notes
        )

        if len(hunks_to_apply) == len(hunks):
            log.info(f"Applying entire change to {file_name}")
            return new_content, None

        elif len(hunks_to_apply) == 0:
            if hunks_to_rework:
                log.info(f"Requesting rework for {len(hunks_to_rework)} changes to {file_name} (0 hunks to apply)")
                return old_content, review_log
            else:
                log.info(f"Rejecting entire change to {file_name} with reason: {llm_response.review_notes}")
                return old_content, None

        log.debug(f"Applying code change to {file_name}:\n{diff_log}")
        new_content = self.apply_diff(file_name, old_content, hunks_to_apply, new_content)
        if hunks_to_rework:
            log.info(f"Requesting further rework for {len(hunks_to_rework)} changes to {file_name}")
            return new_content, review_log
        else:
            return new_content, None

    @staticmethod
    def get_diff_hunks(file_name: str, old_content: str, new_content: str) -> list[str]:
        from_name = "old_" + file_name
        to_name = "to_" + file_name
        from_lines = old_content.splitlines(keepends=True)
        to_lines = new_content.splitlines(keepends=True)
        diff_gen = unified_diff(from_lines, to_lines, fromfile=from_name, tofile=to_name)
        diff_txt = "".join(diff_gen)

        hunks = re.split(r"\n@@", diff_txt, re.MULTILINE)
        result = []
        for i, h in enumerate(hunks):
            if i == 0:
                continue
            txt = h.splitlines()
            txt[0] = "@@" + txt[0]
            result.append("\n".join(txt))
        return result

    def apply_diff(self, file_name: str, old_content: str, hunks: list[str], fallback: str):
        diff = (
            "\n".join(
                [
                    f"--- {file_name}",
                    f"+++ {file_name}",
                ]
                + hunks
            )
            + "\n"
        )
        try:
            fixed_content = self._apply_patch(old_content, diff)
        except Exception as e:
            print(f"Error applying diff: {e}; hoping all changes are valid")
            return fallback

        return fixed_content

    @staticmethod
    def _apply_patch(original: str, patch: str, revert: bool = False):
        original_lines = original.splitlines(True)
        patch_lines = patch.splitlines(True)

        updated_text = ""
        index_original = start_line = 0

        match_index, line_sign = (1, "+") if not revert else (3, "-")

        while index_original < len(patch_lines) and patch_lines[index_original].startswith(("---", "+++")):
            index_original += 1

        while index_original < len(patch_lines):
            match = PATCH_HEADER_PATTERN.match(patch_lines[index_original])
            if not match:
                raise Exception("Bad patch -- regex mismatch [line " + str(index_original) + "]")

            line_number = int(match.group(match_index)) - 1 + (match.group(match_index + 1) == "0")

            if start_line > line_number or line_number > len(original_lines):
                raise Exception("Bad patch -- bad line number [line " + str(index_original) + "]")

            updated_text += "".join(original_lines[start_line:line_number])
            start_line = line_number
            index_original += 1

            while index_original < len(patch_lines) and patch_lines[index_original][0] != "@":
                if index_original + 1 < len(patch_lines) and patch_lines[index_original + 1][0] == "\\":
                    line_content = patch_lines[index_original][:-1]
                    index_original += 2
                else:
                    line_content = patch_lines[index_original]
                    index_original += 1

                if line_content:
                    if line_content[0] == line_sign or line_content[0] == " ":
                        updated_text += line_content[1:]
                    start_line += line_content[0] != line_sign

        updated_text += "".join(original_lines[start_line:])
        return updated_text
