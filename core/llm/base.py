import asyncio
import datetime
import json
from enum import Enum
from time import time
from typing import Any, Callable, Optional, Tuple, AsyncGenerator

import httpx
from openai import OpenAIError, RateLimitError

from core.config import LLMConfig, LLMProvider
from core.log import get_logger
from core.agents.convo import Convo  # Change this line
from core.llm.request_log import LLMRequestLog, LLMRequestStatus
from core.errors import APIError

log = get_logger(__name__)


class LLMError(str, Enum):
    KEY_EXPIRED = "key_expired"
    RATE_LIMITED = "rate_limited"
    GENERIC_API_ERROR = "generic_api_error"


class BaseLLMClient:
    """
    Base asynchronous streaming client for language models.
    """

    provider: LLMProvider

    # List of models that do NOT support setting the 'temperature' parameter
    models_with_fixed_temperature = ["o1-preview", "o1-mini"]  # Add any other models as needed

    # List of models that do NOT support streaming
    models_without_streaming = ["o1-preview", "o1-mini"]  # Add any other models as needed

    def __init__(
        self,
        config: LLMConfig,
        *,
        stream_handler: Optional[Callable] = None,
        error_handler: Optional[Callable] = None,
    ):
        """
        Initialize the client with the given configuration.

        :param config: Configuration for the client.
        :param stream_handler: Optional handler for streamed responses.
        """
        self.config = config
        self.stream_handler = stream_handler
        self.error_handler = error_handler
        self._init_client()

    def _init_client(self):
        raise NotImplementedError()

    async def _make_request(
        self,
        convo: Convo,
        temperature: Optional[float] = None,
        json_mode: bool = False,
    ) -> tuple[str, int, int]:
        """
        Implemented in subclasses.
        """
        raise NotImplementedError()

    async def __call__(
        self,
        convo: Convo,
        *,
        temperature: Optional[float] = None,
        parser: Optional[Callable] = None,
        max_retries: int = 3,
        json_mode: bool = False,
    ) -> Tuple[Any, LLMRequestLog]:
        """
        Invoke the LLM with the given conversation.
        """
        import anthropic
        import groq
        import openai

        if temperature is None:
            temperature = self.config.temperature

        convo = convo.fork()
        request_log = LLMRequestLog(
            provider=self.provider,
            model=self.config.model,
            temperature=temperature,
            prompts=convo.prompt_log,
        )

        prompt_length_kb = len(json.dumps(convo.messages).encode("utf-8")) / 1024
        log.debug(
            f"Calling {self.provider.value} model {self.config.model} (temp={temperature}), prompt length: {prompt_length_kb:.1f} KB"
        )
        t0 = time()

        # Check if the model supports setting 'temperature'
        supports_temperature = self.config.model not in self.models_with_fixed_temperature

        # Check if the model supports streaming
        supports_streaming = self.config.model not in self.models_without_streaming
        if not supports_streaming:
            self.stream_output = None  # Disable streaming for models that do not support it

        remaining_retries = max_retries
        while True:
            if remaining_retries == 0:
                # We've run out of auto-retries
                if request_log.error:
                    last_error_msg = f"Error connecting to the LLM: {request_log.error}"
                else:
                    last_error_msg = "Error parsing LLM response"

                # If we can, ask the user if they want to keep retrying
                if self.error_handler:
                    should_retry = await self.error_handler(LLMError.GENERIC_API_ERROR, message=last_error_msg)
                    if should_retry:
                        remaining_retries = max_retries
                        continue

                # They don't want to retry (or we can't ask them), raise the last error and stop Pythagora
                raise APIError(last_error_msg)

            remaining_retries -= 1
            request_log.messages = convo.messages[:]
            request_log.response = None
            request_log.status = LLMRequestStatus.SUCCESS
            request_log.error = None
            response = None

            try:
                # Only pass 'temperature' if the model supports it
                if supports_temperature:
                    response, prompt_tokens, completion_tokens = await self._make_request(
                        convo,
                        temperature=temperature,
                        json_mode=json_mode,
                    )
                else:
                    response, prompt_tokens, completion_tokens = await self._make_request(
                        convo,
                        temperature=None,  # Do not set temperature
                        json_mode=json_mode,
                    )
            except Exception as err:
                # Handle all exceptions in a generic way
                log.warning(f"API error: {err}", exc_info=True)
                request_log.error = str(err)
                request_log.status = LLMRequestStatus.ERROR
                
                if isinstance(err, RateLimitError):
                    wait_time = self.rate_limit_sleep(err)
                    if wait_time:
                        message = f"We've hit {self.config.provider.value} rate limit. Sleeping for {wait_time.seconds} seconds..."
                        if self.error_handler:
                            await self.error_handler(LLMError.RATE_LIMITED, message)
                        await asyncio.sleep(wait_time.seconds)
                        continue
                
                # For other errors, raise an APIError
                raise APIError(str(err)) from err

            request_log.response = response

            request_log.prompt_tokens += prompt_tokens
            request_log.completion_tokens += completion_tokens
            if parser:
                try:
                    response = parser(response)
                    break
                except ValueError as err:
                    request_log.error = f"Error parsing response: {err}"
                    request_log.status = LLMRequestStatus.ERROR
                    log.debug(f"Error parsing LLM response: {err}, asking LLM to retry", exc_info=True)
                    convo.assistant(response)
                    convo.user(f"Error parsing response: {err}. Please output your response EXACTLY as requested.")
                    continue
            else:
                break

        t1 = time()
        request_log.duration = t1 - t0

        log.debug(
            f"Total {self.provider.value} response time {request_log.duration:.2f}s, {request_log.prompt_tokens} prompt tokens, {request_log.completion_tokens} completion tokens used"
        )

        return response, request_log

    async def api_check(self) -> bool:
        """
        Perform an LLM API check.

        :return: True if the check was successful, False otherwise.
        """

        convo = Convo()
        msg = "This is a connection test. If you can see this, please respond only with 'START' and nothing else."
        convo.user(msg)
        resp, _log = await self(convo)
        return bool(resp)

    @staticmethod
    def for_provider(provider: LLMProvider) -> type["BaseLLMClient"]:
        """
        Return LLM client for the specified provider.

        :param provider: Provider to return the client for.
        :return: Client class for the specified provider.
        """
        from .anthropic_client import AnthropicClient
        from .azure_client import AzureClient
        from .groq_client import GroqClient
        from .openai_client import OpenAIClient

        if provider == LLMProvider.OPENAI:
            return OpenAIClient
        elif provider == LLMProvider.ANTHROPIC:
            return AnthropicClient
        elif provider == LLMProvider.GROQ:
            return GroqClient
        elif provider == LLMProvider.AZURE:
            return AzureClient
        else:
            raise ValueError(f"Unsupported LLM provider: {provider.value}")

    def rate_limit_sleep(self, err: Exception) -> Optional[datetime.timedelta]:
        """
        Return how long we need to sleep because of rate limiting.

        These are computed from the response headers that each LLM returns.
        For details, check the implementation for the specific LLM. If there
        are no rate limiting headers, we assume that the request should not
        be retried and return None (this will be the case for insufficient
        quota/funds in the account).

        :param err: RateLimitError that was raised by the LLM client.
        :return: optional timedelta to wait before trying again
        """

        raise NotImplementedError()

    def model_supports_streaming(self):
        return self.config.model not in self.models_without_streaming

    async def stream_response(self, chunk: str):
        if self.stream_output:
            await self.ui.send_message(chunk, source=self.agent_name)

    async def stream_call(self, convo: Convo, **kwargs) -> str:
        full_response = ""
        async for chunk in self._stream_call(convo, **kwargs):
            full_response += chunk
            await self.stream_response(chunk)
        return full_response

    async def _stream_call(self, convo: Convo, **kwargs) -> AsyncGenerator[str, None]:
        raise NotImplementedError()
