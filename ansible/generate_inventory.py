#!/usr/bin/env python3
"""
Generates an Ansible inventory INI file from Terraform JSON output.
Reads from stdin and writes to stdout.
"""
import sys
import json

def main():
    try:
        tf_data = json.load(sys.stdin)
    except Exception as e:
        print(f"Error: Failed to parse JSON from stdin: {e}", file=sys.stderr)
        sys.exit(1)

    # Helper function to extract value safely
    def get_val(key):
        if key in tf_data and "value" in tf_data[key]:
            return tf_data[key]["value"]
        print(f"Error: Key '{key}' not found in Terraform output.", file=sys.stderr)
        sys.exit(1)

    engine_pub = get_val("engine_public_ip")
    inference_priv = get_val("inference_worker_private_ip")
    caller_priv = get_val("caller_worker_private_ip")

    inventory = f"""[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=../terraform/iii-key.pem
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'

[engine_gateway]
engine_gateway_vm ansible_host={engine_pub}

[inference_worker]
inference_worker_vm ansible_host={inference_priv} ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand="ssh -i ../terraform/iii-key.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p ubuntu@{engine_pub}"'

[caller_worker]
caller_worker_vm ansible_host={caller_priv} ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand="ssh -i ../terraform/iii-key.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p ubuntu@{engine_pub}"'
"""
    print(inventory)

if __name__ == "__main__":
    main()
