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

def run_inference_handler(payload: Dict[str, str | List[Dict[str, Any]]] = None) -> Dict[str, Any]:
    if not isinstance(payload, dict):
        payload = {}
    messages = payload.get("messages", [])
    user_query = "hello"
    if messages and len(messages) > 0:
        user_query = messages[-1].get("content", "hello")

    logger.info(f"Inference request received: '{user_query}'")

    if tokenizer is not None and model is not None:
        try:
            # Gemma-3 has a built-in chat template. We apply it to format the conversation sequence.
            if messages:
                prompt = tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
            else:
                prompt = user_query
            
            logger.info(f"Generated chat prompt: {prompt}")
            inputs = tokenizer(prompt, return_tensors="pt").to(model.device)
            
            with torch.no_grad():
                output_ids = model.generate(
                    **inputs,
                    max_new_tokens=256,
                    do_sample=True,
                    temperature=0.7,
                    top_k=50,
                    top_p=0.9,
                    repetition_penalty=1.2,
                    pad_token_id=tokenizer.eos_token_id
                )
            
            # Extract only the newly generated tokens
            input_len = inputs["input_ids"].shape[-1]
            generated_tokens = output_ids[0][input_len:]
            response_text = tokenizer.decode(generated_tokens, skip_special_tokens=True).strip()
            logger.info(f"Model response successfully generated: '{response_text}'")
            
        except Exception as e:
            logger.error(f"Error during model generation: {e}")
            response_text = f"Error during model generation: {e}"
    else:
        logger.error("Gemma model not loaded. Running fallback mock response.")
        response_text = f"Hello! (Fallback Mock Response) You queried: '{user_query}'"

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
