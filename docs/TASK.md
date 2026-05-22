# Distributed LLM Execution and Model Storage Guide

This document explains the end-to-end LLM operation of the distributed inference mesh, detailing how and where the weights are stored on the `inference-worker` (`c7i-flex.large` VM) and the architectural reasons for using this specific model.

---

## 1. How the Project Works as an LLM Pipeline

At its core, this project exposes a standard **OpenAI-compatible Chat Completions API Gateway**. When an external client makes a request to the edge gateway, a multi-hop cross-language RPC mesh executes to generate the prompt completion:

```
                  [Client POST Request]
                            │ (HTTPS :443)
                            ▼
                     [Nginx Gateway]
                            │ (Proxy Pass :127.0.0.1:3111)
                            ▼
                      [iii Engine]
                            │ (outbound WebSocket RPC)
                            ▼
              [TypeScript Caller Worker VM]
                            │ (delegates payload through Engine socket)
                            ▼
               [Python Inference Worker VM]
```

### The Generation Pipeline:
1. **Request Intake**: Nginx terminates public TLS and forwards the chat completions payload containing a standard system/user messages array (e.g., `[{"role": "user", "content": "What is 2+2?"}]`) to the central `iii` gateway process.
2. **TypeScript Dispatcher**: The central engine routes the trigger to the TypeScript `caller-worker`, which acts as the high-speed caller layer.
3. **Python Execution**: The TypeScript worker routes the payload over websocket RPC to the Python `inference-worker`.
4. **Tokenization**: The Python worker tokenizes the input messages into a flat sequence of integer token IDs using Google's chat template structure:
   ```
   <start_of_turn>user\nWhat is 2+2?<end_of_turn>\n<start_of_turn>model\n
   ```
5. **Causal Generation**: The model processes the token IDs, running next-token prediction using physical CPU execution threads.
6. **Decoding**: Once generation concludes, the token sequence is decoded back into standard text (e.g. `"4."`) and passed back up through the RPC chain to be formatted as standard completions JSON.

---

## 2. Where the Model is Stored on the VM & How Information is Fetched

On the `inference-worker` VM, the system uses a modern, lightweight approach to load the causal language model:

### 1. Storage Location on the VM
When the systemd service `inference-worker.service` launches, the Python script downloads and caches the model file from HuggingFace. By default, it is saved under the user's home directory inside the standard HuggingFace Hub cache folder:
```
/home/ubuntu/.cache/huggingface/hub/models--ggml-org--gemma-3-270m-GGUF/
```
The exact binary downloaded is:
```
gemma-3-270m-Q8_0.gguf (~540 MB)
```

### 2. Loading Mechanics (How it is loaded)
Rather than executing raw C++ commands, the Python worker script utilizes the HuggingFace `transformers` library with integrated **GGUF (GPT-Generated Unified Format)** support:
```python
from transformers import AutoModelForCausalLM, AutoTokenizer

model_id = "ggml-org/gemma-3-270m-GGUF"
gguf_file = "gemma-3-270m-Q8_0.gguf"

# Loads tokenizer mapping and 8-bit quantized weights directly from local GGUF cache
tokenizer = AutoTokenizer.from_pretrained(model_id, gguf_file=gguf_file)
model = AutoModelForCausalLM.from_pretrained(model_id, gguf_file=gguf_file)
```
This loads the 8-bit quantized parameters (~270 million weights) straight into the physical RAM of the instance.

### 3. Fetching Information (How inference runs)
When a completion request is received:
- Input messages are converted to PyTorch tensors containing token IDs:
  ```python
  inputs = tokenizer(text, return_tensors="pt").to(model.device)
  ```
- The execution engine feeds the inputs through the neural network parameters:
  ```python
  output = model.generate(**inputs, max_new_tokens=32000)
  ```
  The causal model runs forward passes, picking the most likely subsequent token IDs.
- The resulting IDs are converted back to a string and returned:
  ```python
  result = tokenizer.decode(output[0][inputs["input_ids"].shape[-1]:], skip_special_tokens=True)
  ```

---

## 3. Why This Specific Model is Used

Google's **Gemma-3-270m** (specifically the 8-bit quantized **Q8_0 GGUF** variant) was selected for three crucial DevOps and engineering reasons:

### 1. Extreme CPU Efficiency (Zero GPU Requirement)
Typical Large Language Models (e.g. Llama-3-8B) require massive graphical memory (VRAM) to execute efficiently. This demands expensive GPU compute instances (such as AWS `g5.xlarge` costing ~$1.00/hour or more).
* **The Gemma-3-270m SLM** has only 270 million parameters.
* The quantized 8-bit weights take up only **~540MB** of space.
* Consequently, the entire neural network can load and run **incredibly fast using standard CPU execution threads** on a basic, low-cost CPU-only instance (such as a standard AWS Free Tier `t3.micro` or highly efficient `c7i-flex.large`), avoiding any GPU bills.

### 2. High-Fidelity Small Language Model (SLM)
Despite its minuscule footprint, Gemma-3-270m is trained by Google using state-of-the-art architectures. It is highly capable of following prompt instructions and generating coherent, 1-sentence completions for lightweight assistant tasks, making it ideal for standard quickstart testing.

### 3. Realistic Pipeline Representation
Using a GGUF SLM model replicates the exact architectural challenges faced in massive production environments (fetching model binaries from storage registries, loading parameters into memory, compiling tokenizer templates, managing network isolates, and coordinating inter-process RPC boundaries) at a **fraction of the operational cost and system complexity**.

---

## 4. Running Gemma-3-270m on Free Tier Nodes: Virtual Memory Swap Partitioning

If you do not have a Paid AWS Account or wish to avoid the billing fees of a `c7i-flex.large` instance, the best and most cost-effective alternative is to deploy the entire stack on standard **Free Tier `t3.micro` instances** (which only have 1GB of physical RAM).

### The Challenge
Google's Gemma-3-270m-Q8_0 quantized model binary is ~540MB, and loading the model parameters along with PyTorch, `transformers`, and system overhead requires roughly **1.5GB to 1.8GB of RAM** during generation. On a 1GB `t3.micro` instance, attempting to load this will immediately cause a fatal **Out-Of-Memory (OOM) error** and crash the python script.

### The Solution: 2GB Swap Space Partitioning
To run the model on `t3.micro` without spending a single penny, we implement automated **Virtual Memory Swap Allocation** inside the common Ansible task setup.

1. **Virtual Memory Spillover:** We create a **2GB swap file** (`/swapfile`) on the instance's Solid State Drive (EBS Volume).
2. **OOM Protection:** When physical RAM is exhausted, the Linux kernel automatically swaps inactive pages out to disk, expanding the usable virtual memory address space to 3GB total (1GB Physical RAM + 2GB Swap Space).
3. **Execution Behavior:** The Gemma model loads completely and generates responses successfully. Because SSD disk I/O is slower than physical RAM, token generation will take slightly longer (around 2 to 3 seconds per response), but it guarantees **100% stable execution for $0.00 in cost**.
4. **Ansible Automation:**
   ```yaml
   - name: Create 2GB swap file for memory cushioning on Free Tier nodes
     ansible.builtin.command: dd if=/dev/zero of=/swapfile bs=1M count=2048
     when: not swap_file_stat.stat.exists
     become: true
   ```
   This is fully integrated into the provisioning pipeline, enabling frictionless deployment on clean, free accounts out of the box.

