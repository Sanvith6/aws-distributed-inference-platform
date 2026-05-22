# Running the Multi-Account Terraform Deployment

The Terraform code is now structured to deploy resources across **two separate AWS accounts** simultaneously:
1. **Free Tier Account (Default)**: Hosts the VPC, subnets, NAT instance, Engine Gateway, and Caller Worker.
2. **Paid Account**: Hosts the compute-efficient `c7i-flex.large` Inference Worker.

## Authentication Steps

Since Terraform needs to authenticate to both accounts at the same time, you must set up your environment variables before running the code.

Open your PowerShell terminal and run the following commands (replace the placeholder values with your actual keys):

```powershell
# 1. Set credentials for the Free Tier Account (Default Provider)
$env:AWS_ACCESS_KEY_ID="<your-free-tier-access-key>"
$env:AWS_SECRET_ACCESS_KEY="<your-free-tier-secret-key>"
# $env:AWS_SESSION_TOKEN="<your-session-token>" # (Only needed if using temporary STS credentials)

# 2. Set credentials for the Paid Account (Passed to Terraform via TF_VAR)
$env:TF_VAR_paid_access_key="<your-paid-account-access-key>"
$env:TF_VAR_paid_secret_key="<your-paid-account-secret-key>"
```

## Deployment

Once your keys are exported, you can deploy the infrastructure:

```powershell
cd c:\project\alchemist\devops\terraform

# Initialize the new providers
terraform init

# Apply the infrastructure
terraform apply
```

This will spin up the `c7i-flex.large` inference worker in the paid account and all the networking in the free-tier account.
