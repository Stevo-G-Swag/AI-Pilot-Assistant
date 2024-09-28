import datetime
import re
from typing import Optional

import tiktoken
from httpx import Timeout
from openai import AsyncOpenAI, OpenAIError, RateLimitError

from core.config import LLMProvider
from core.llm.base import BaseLLMClient
from core.llm.convo import Convo
from core.log import get_logger

log = get_logger(__name__)
tokenizer = tiktoken.get_encoding("cl100k_base")


class OpenAIClient(BaseLLMClient):
    provider = LLMProvider.OPENAI

    def _init_client(self):
        self.client = AsyncOpenAI(
            api_key=self.config.api_key,
            base_url=self.config.base_url,
            timeout=Timeout(
                max(self.config.connect_timeout, self.config.read_timeout),
                connect=self.config.connect_timeout,
                read=self.config.read_timeout,
            ),
        )

    async def _make_request(
        self,
        convo: Convo,
        temperature: Optional[float] = None,
        json_mode: bool = False,
    ) -> tuple[str, int, int]:
        completion_kwargs = {
            "model": self.config.model,
            "messages": [
                {"role": "user" if msg["role"] == "system" else msg["role"], "content": msg["content"]}
                for msg in convo.messages
            ],
            "temperature": temperature if temperature is not None else self.config.temperature,
            "stream": self.stream_output is not None,
        }

        if json_mode:
            completion_kwargs["response_format"] = {"type": "json_object"}

        try:
            response = await self.client.chat.completions.create(**completion_kwargs)
            
            if self.stream_output is not None:
                response_content = ""
                prompt_tokens = 0
                completion_tokens = 0
                async for chunk in response:
                    content = chunk.choices[0].delta.content
                    if content:
                        response_content += content
                        if self.stream_handler:
                            await self.stream_handler(content)
                # Estimate token usage for streaming responses
                prompt_tokens = sum(len(tokenizer.encode(m["content"])) for m in convo.messages)
                completion_tokens = len(tokenizer.encode(response_content))
            else:
                response_content = response.choices[0].message.content
                prompt_tokens = response.usage.prompt_tokens
                completion_tokens = response.usage.completion_tokens

                if self.stream_handler:
                    await self.stream_handler(response_content)
                    await self.stream_handler(None)  # Indicate stream end

            return response_content, prompt_tokens, completion_tokens
        except OpenAIError as e:
            log.error(f"OpenAI API error: {e}")
            raise

    def rate_limit_sleep(self, err: RateLimitError) -> Optional[datetime.timedelta]:
        headers = err.response.headers
        if "x-ratelimit-remaining-tokens" not in headers:
            return None

        remaining_tokens = headers["x-ratelimit-remaining-tokens"]
        time_regex = r"(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?"
        if remaining_tokens == '0':
            match = re.search(time_regex, headers.get("x-ratelimit-reset-tokens", ""))
        else:
            match = re.search(time_regex, headers.get("x-ratelimit-reset-requests", ""))

        if match:
            hours = int(match.group(1)) if match.group(1) else 0
            minutes = int(match.group(2)) if match.group(2) else 0
            seconds = int(match.group(3)) if match.group(3) else 0
            total_seconds = hours * 3600 + minutes * 60 + seconds
        else:
            total_seconds = 5

        return datetime.timedelta(seconds=total_seconds)


__all__ = ["OpenAIClient"]
