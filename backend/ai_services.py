import os
from openai import OpenAI
from litellm import completion
from huggingface_hub import InferenceClient
from github import Github

OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY")
OPENROUTER_API_KEY = os.environ.get("OPENROUTER_API_KEY")
HUGGINGFACE_API_KEY = os.environ.get("HUGGINGFACE_API_KEY")
GITHUB_API_KEY = os.environ.get("GITHUB_API_KEY")

def send_openai_request(prompt: str, model: str = "gpt-4o") -> str:
    if not OPENAI_API_KEY:
        return "Error: OpenAI API key not found in environment variables."
    
    openai_client = OpenAI(api_key=OPENAI_API_KEY)
    completion = openai_client.chat.completions.create(
        model=model, messages=[{"role": "user", "content": prompt}], max_tokens=500
    )
    content = completion.choices[0].message.content
    if not content:
        raise ValueError("OpenAI returned an empty response.")
    return content

def send_openrouter_request(prompt: str, model: str = "openai/gpt-3.5-turbo") -> str:
    if not OPENROUTER_API_KEY:
        return "Error: OpenRouter API key not found in environment variables."
    
    response = completion(
        model=model,
        messages=[{"role": "user", "content": prompt}],
        api_base="https://openrouter.ai/api/v1",
        api_key=OPENROUTER_API_KEY
    )
    return response.choices[0].message.content

def send_huggingface_request(prompt: str, model: str = "microsoft/phi-2") -> str:
    if not HUGGINGFACE_API_KEY:
        return "Error: Hugging Face API key not found in environment variables."
    
    client = InferenceClient(model=model, token=HUGGINGFACE_API_KEY)
    response = client.text_generation(prompt, max_new_tokens=500)
    return response

def send_github_request(prompt: str, model: str = "github/copilot-chat") -> str:
    if not GITHUB_API_KEY:
        return "Error: GitHub API key not found in environment variables."
    
    g = Github(GITHUB_API_KEY)
    copilot = g.get_user().get_copilot_chat()
    response = copilot.create_chat(model=model, messages=[{"role": "user", "content": prompt}])
    return response.choices[0].message.content

def generate_code(context: str, prompt: str, model: str = "openai/gpt-4o") -> str:
    full_prompt = f"Context: {context}\n\nTask: {prompt}\n\nGenerate code for this task:"
    return send_request(full_prompt, model)

def explain_error(error_message: str, code_snippet: str, model: str = "openai/gpt-4o") -> str:
    full_prompt = f"Error message: {error_message}\n\nCode snippet:\n{code_snippet}\n\nExplain this error and suggest a fix:"
    return send_request(full_prompt, model)

def answer_question(question: str, context: str, model: str = "openai/gpt-4o") -> str:
    full_prompt = f"Context: {context}\n\nQuestion: {question}\n\nAnswer:"
    return send_request(full_prompt, model)

def suggest_refactoring(code_snippet: str, model: str = "openai/gpt-4o") -> str:
    full_prompt = f"""
    Analyze the following code snippet and suggest advanced refactoring improvements:
    
    {code_snippet}
    
    Consider the following aspects in your suggestions:
    1. Code readability and maintainability
    2. Performance optimizations
    3. Design patterns that could be applied
    4. Potential bugs or edge cases
    5. Adherence to SOLID principles
    6. Testability improvements
    
    Provide detailed explanations for each suggestion, including code examples where appropriate.
    """
    return send_request(full_prompt, model)

def send_request(prompt: str, model: str) -> str:
    if model.startswith("openai/"):
        return send_openai_request(prompt, model.split("/")[1])
    elif model.startswith("openrouter/"):
        return send_openrouter_request(prompt, model.split("/", 1)[1])
    elif model.startswith("huggingface/"):
        return send_huggingface_request(prompt, model.split("/", 1)[1])
    elif model.startswith("github/"):
        return send_github_request(prompt, model)
    else:
        raise ValueError(f"Unsupported model: {model}")
