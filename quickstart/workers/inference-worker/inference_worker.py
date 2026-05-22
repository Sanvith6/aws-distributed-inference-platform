import os
from typing import Any, Dict, List

from iii import InitOptions, Logger, register_worker

# Initialize the worker and connect to the central engine
iii = register_worker(
    os.environ.get("III_URL", "ws://localhost:49134"),
    InitOptions(worker_name="math-worker"),
)
logger = Logger()

logger.info("Initializing inference-worker in lightweight mock fallback mode...")

def run_inference_handler(payload: Dict[str, str | List[Dict[str, Any]]] = None) -> Dict[str, Any]:
    if not isinstance(payload, dict):
        payload = {}
    messages = payload.get("messages", [])
    user_query = "hello"
    if messages and len(messages) > 0:
        # Extrapolate the user's latest query
        user_query = messages[-1].get("content", "hello")

    logger.info(f"Inference request received: '{user_query}'")

    # Check if the query contains a basic arithmetic expression (e.g. 2+6, 10-5, 3*4)
    import re
    math_match = re.search(r'(\d+)\s*([\+\-\*\/])\s*(\d+)', user_query)
    if math_match:
        try:
            num1 = int(math_match.group(1))
            op = math_match.group(2)
            num2 = int(math_match.group(3))
            if op == '+':
                mock_response = str(num1 + num2)
            elif op == '-':
                mock_response = str(num1 - num2)
            elif op == '*':
                mock_response = str(num1 * num2)
            elif op == '/':
                mock_response = str(num1 / num2) if num2 != 0 else "Error: division by zero"
        except Exception as e:
            logger.error(f"Error parsing math expression: {e}")
            mock_response = f"Hello! This is a distributed AI inference response via the iii RPC mesh. You queried: '{user_query}'"
    else:
        # Generate a rich mock completion response conforming to the expected OpenAI format
        mock_response = f"Hello! This is a distributed AI inference response via the iii RPC mesh. You queried: '{user_query}'"
        
    return {
        "choices": [
            {
                "message": {
                    "role": "assistant",
                    "content": mock_response
                }
            }
        ],
        "text": mock_response
    }

# Register the target function on the central WebSocket RPC registry
iii.register_function("inference::run_inference", run_inference_handler)

print("Inference worker started - listening for calls")
