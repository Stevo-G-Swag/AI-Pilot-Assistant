import os
from openai import OpenAI

OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY")

def send_openai_request(prompt: str) -> str:
    if not OPENAI_API_KEY:
        return "Error: OpenAI API key not found in environment variables."
    
    openai_client = OpenAI(api_key=OPENAI_API_KEY)
    completion = openai_client.chat.completions.create(
        model="gpt-4o", messages=[{"role": "user", "content": prompt}], max_tokens=500
    )
    content = completion.choices[0].message.content
    if not content:
        raise ValueError("OpenAI returned an empty response.")
    return content

def generate_code(context: str, prompt: str) -> str:
    full_prompt = f"Context: {context}\n\nTask: {prompt}\n\nGenerate code for this task:"
    return send_openai_request(full_prompt)

def explain_error(error_message: str, code_snippet: str) -> str:
    full_prompt = f"Error message: {error_message}\n\nCode snippet:\n{code_snippet}\n\nExplain this error and suggest a fix:"
    return send_openai_request(full_prompt)

def answer_question(question: str, context: str) -> str:
    full_prompt = f"Context: {context}\n\nQuestion: {question}\n\nAnswer:"
    return send_openai_request(full_prompt)
