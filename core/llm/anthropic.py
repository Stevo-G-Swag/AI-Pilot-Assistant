from anthropic import AsyncAnthropic
from anthropic.types import AsyncStream
from typing import AsyncGenerator

from core.llm.base import BaseLLMClient
from core.agents.convo import Convo  # Change this line
from core.errors import APIError

class AnthropicLLMClient(BaseLLMClient):
    # ... existing code ...

    async def __call__(self, convo: Convo, **kwargs) -> str:  # Change AgentConvo to Convo
        if self.stream_output:
            return await self.stream_call(convo, **kwargs)
        else:
            return await self._non_streaming_call(convo, **kwargs)

    async def _non_streaming_call(self, convo: Convo, **kwargs) -> str:  # Change AgentConvo to Convo
        # ... existing non-streaming implementation ...

    async def _stream_call(self, convo: Convo, **kwargs) -> AsyncGenerator[str, None]:  # Change AgentConvo to Convo
        messages = convo.to_anthropic_messages()
        client = AsyncAnthropic(api_key=self.config.anthropic_api_key)
        
        stream: AsyncStream = await client.messages.create(
            model=self.config.model,
            messages=messages,
            max_tokens=self.config.max_tokens,
            temperature=self.config.temperature,
            stream=True
        )

        async for chunk in stream:
            if chunk.content:
                yield chunk.content