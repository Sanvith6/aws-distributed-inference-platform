import os
import sys

# Standard Python HuggingFace Transformers GGUF-loading packaging version monkeypatch.
# Prevents a known packaging.version.InvalidVersion crash on 'N/A' when loading GGUF on VM nodes.
try:
    import transformers.utils.import_utils
    transformers.utils.import_utils.is_gguf_available = lambda *args, **kwargs: True
    import transformers.utils
    transformers.utils.is_gguf_available = lambda *args, **kwargs: True
except Exception:
    pass

import torch
from typing import Any, Dict, List
from transformers import AutoModelForCausalLM, AutoTokenizer
from iii import InitOptions, Logger, register_worker

# Initialize the worker and connect to the central engine
iii = register_worker(
    os.environ.get("III_URL", "ws://localhost:49134"),
    InitOptions(worker_name="inference-worker"),
)
logger = Logger()

logger.info("Initializing inference-worker and loading Gemma-3 SLM model...")

model_id = "ggml-org/gemma-3-270m-GGUF"
gguf_file = "gemma-3-270m-Q8_0.gguf"

try:
    logger.info(f"Loading tokenizer from {model_id}...")
    tokenizer = AutoTokenizer.from_pretrained(model_id, gguf_file=gguf_file)
    
    logger.info(f"Loading GGUF model weights from {model_id} ({gguf_file})...")
    model = AutoModelForCausalLM.from_pretrained(model_id, gguf_file=gguf_file)
    logger.info("Model loaded successfully!")
except Exception as e:
    logger.error(f"Error loading Gemma model: {e}")
    tokenizer = None
    model = None


def build_gemma_prompt(messages: List[Dict[str, Any]], default_query: str) -> str:
    system_parts: List[str] = []
    conversation: List[Dict[str, str]] = []

    for message in messages:
        if not isinstance(message, dict):
            continue
        role = str(message.get("role", "user")).lower()
        content = str(message.get("content", "")).strip()
        if not content:
            continue
        if role == "system":
            system_parts.append(content)
        elif role == "assistant":
            conversation.append({"role": "model", "content": content})
        else:
            conversation.append({"role": "user", "content": content})

    if not conversation:
        conversation.append({"role": "user", "content": default_query})

    if system_parts:
        instruction = "\n".join(system_parts)
        first_user_index = next(
            (index for index, item in enumerate(conversation) if item["role"] == "user"),
            None,
        )
        folded_content = f"System instructions:\n{instruction}\n\nUser request:\n"
        if first_user_index is None:
            conversation.insert(0, {"role": "user", "content": folded_content + default_query})
        else:
            conversation[first_user_index]["content"] = (
                folded_content + conversation[first_user_index]["content"]
            )

    prompt = "<bos>"
    for item in conversation:
        prompt += f"<start_of_turn>{item['role']}\n{item['content']}<end_of_turn>\n"
    return prompt + "<start_of_turn>model\n"


def render_prompt(messages: List[Dict[str, Any]], default_query: str) -> str:
    if tokenizer is not None and getattr(tokenizer, "chat_template", None):
        try:
            return tokenizer.apply_chat_template(
                messages,
                tokenize=False,
                add_generation_prompt=True,
            )
        except Exception as e:
            logger.error(f"Tokenizer chat template failed, using manual Gemma prompt: {e}")
    return build_gemma_prompt(messages, default_query)


def clean_model_response(text: str) -> str:
    cleaned = text.split("<end_of_turn>", 1)[0]
    cleanup_tokens = [
        "<start_of_turn>model",
        "<start_of_turn>assistant",
        "<start_of_turn>user",
        "<eos>",
    ]
    for token in cleanup_tokens:
        cleaned = cleaned.replace(token, "")
    return cleaned.strip()


def run_inference_handler(payload: Dict[str, str | List[Dict[str, Any]]] = None) -> Dict[str, Any]:
    if not isinstance(payload, dict):
        payload = {}
    messages = payload.get("messages", [])
    if not isinstance(messages, list):
        messages = []
    user_query = "hello"
    if messages and len(messages) > 0:
        last_message = messages[-1]
        if isinstance(last_message, dict):
            user_query = str(last_message.get("content", "hello"))

    logger.info(f"Inference request received: '{user_query}'")

    if tokenizer is not None and model is not None:
        try:
            prompt = render_prompt(messages, user_query)
            logger.info(f"Generated chat prompt: {prompt}")
            inputs = tokenizer(prompt, return_tensors="pt").to(model.device)
            
            with torch.no_grad():
                output_ids = model.generate(
                    **inputs,
                    max_new_tokens=80,
                    do_sample=True,
                    temperature=0.7,
                    top_k=40,
                    top_p=0.9,
                    repetition_penalty=1.6,
                    no_repeat_ngram_size=3,
                    pad_token_id=tokenizer.eos_token_id
                )
            
            # Extract only the newly generated tokens
            input_len = inputs["input_ids"].shape[-1]
            generated_tokens = output_ids[0][input_len:]
            response_text = clean_model_response(
                tokenizer.decode(generated_tokens, skip_special_tokens=True)
            )
            logger.info(f"Model response successfully generated: '{response_text}'")
            
        except Exception as e:
            logger.error(f"Error during model generation: {e}")
            response_text = f"Error during model generation: {e}"
    else:
        logger.error("Gemma model not loaded; returning explicit runtime error.")
        response_text = "Error during model generation: Gemma model failed to load"

    return {
        "choices": [
            {
                "message": {
                    "role": "assistant",
                    "content": response_text
                }
            }
        ],
        "text": response_text
    }

# Register the target function on the central WebSocket RPC registry
iii.register_function("inference::run_inference", run_inference_handler)

print("Inference worker started - listening for calls")
