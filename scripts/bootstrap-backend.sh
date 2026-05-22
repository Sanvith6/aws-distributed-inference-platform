#!/usr/bin/env python3
"""
AWS Remote State Bootstrapper Script.
Creates the S3 bucket (with versioning enabled) and DynamoDB table
needed for the Terraform remote state backend.
"""
import sys
import subprocess
import json

def run_cmd(cmd, check=True):
    try:
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=check)
        return res.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"Error executing command: {' '.join(cmd)}\nStdout: {e.stdout}\nStderr: {e.stderr}", file=sys.stderr)
        if check:
            sys.exit(e.returncode)
        return None

def check_aws_cli():
    print("[*] Checking AWS CLI installation...")
    try:
        version = run_cmd(["aws", "--version"])
        print(f"[+] Found AWS CLI: {version}")
    except FileNotFoundError:
        print("[-] Error: AWS CLI is not installed or not in PATH.", file=sys.stderr)
        print("    Please install the AWS CLI (https://aws.amazon.com/cli/) and try again.", file=sys.stderr)
        sys.exit(1)

    print("[*] Checking AWS CLI authentication state...")
    identity = run_cmd(["aws", "sts", "get-caller-identity"], check=False)
    if not identity:
        print("[-] Error: AWS CLI is not authenticated or lacks connectivity.", file=sys.stderr)
        print("    Please run 'aws configure' to set up credentials.", file=sys.stderr)
        sys.exit(1)
    
    parsed = json.loads(identity)
    print(f"[+] Authenticated as IAM Entity: {parsed.get('Arn')}")

def bootstrap(region="us-east-1"):
    check_aws_cli()

    bucket_name = "iii-devops-tfstate"
    table_name = "iii-devops-tflock"

    print(f"\n[*] Bootstrapping backend in region: {region}")

    # Create S3 Bucket
    print(f"[*] Checking if S3 bucket '{bucket_name}' exists...")
    buckets = run_cmd(["aws", "s3api", "list-buckets"])
    buckets_json = json.loads(buckets)
    exists = any(b.get("Name") == bucket_name for b in buckets_json.get("Buckets", []))

    if not exists:
        print(f"[*] Creating S3 bucket '{bucket_name}'...")
        # For us-east-1, LocationConstraint must not be specified
        if region == "us-east-1":
            run_cmd(["aws", "s3api", "create-bucket", "--bucket", bucket_name, "--region", region])
        else:
            run_cmd([
                "aws", "s3api", "create-bucket", 
                "--bucket", bucket_name, 
                "--region", region, 
                "--create-bucket-configuration", f"LocationConstraint={region}"
            ])
        print(f"[+] Created bucket '{bucket_name}' successfully.")
    else:
        print(f"[+] S3 bucket '{bucket_name}' already exists. Skipping creation.")

    # Enable Versioning
    print(f"[*] Enabling bucket versioning on '{bucket_name}'...")
    run_cmd([
        "aws", "s3api", "put-bucket-versioning", 
        "--bucket", bucket_name, 
        "--versioning-configuration", "Status=Enabled"
    ])
    print("[+] Versioning enabled.")

    # Create DynamoDB table
    print(f"[*] Checking if DynamoDB table '{table_name}' exists...")
    tables_raw = run_cmd(["aws", "dynamodb", "list-tables", "--region", region])
    tables = json.loads(tables_raw).get("TableNames", [])

    if table_name not in tables:
        print(f"[*] Creating DynamoDB locking table '{table_name}'...")
        run_cmd([
            "aws", "dynamodb", "create-table",
            "--table-name", table_name,
            "--attribute-definitions", "AttributeName=LockID,AttributeType=S",
            "--key-schema", "AttributeName=LockID,KeyType=HASH",
            "--billing-mode", "PAY_PER_REQUEST",
            "--region", region
        ])
        print(f"[+] Created DynamoDB table '{table_name}' successfully.")
    else:
        print(f"[+] DynamoDB table '{table_name}' already exists. Skipping creation.")

    print("\n[+] Bootstrap complete! Terraform S3 Remote State backend is ready.")
    print("    You may now run: cd terraform && terraform init")

if __name__ == "__main__":
    region_arg = sys.argv[1] if len(sys.argv) > 1 else "us-east-1"
    bootstrap(region_arg)
