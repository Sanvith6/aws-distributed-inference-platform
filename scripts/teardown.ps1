# PowerShell Teardown Script to clean up and destroy all provisioned infrastructure
$ErrorActionPreference = "Stop"

Write-Host "==========================================================================" -ForegroundColor Yellow
Write-Host " Starting Teardown of Distributed Inference Infrastructure (AWS)" -ForegroundColor Yellow
Write-Host "==========================================================================" -ForegroundColor Yellow

Push-Location terraform
terraform destroy -auto-approve
Pop-Location

Write-Host "==========================================================================" -ForegroundColor Yellow
Write-Host " [OK] Infrastructure successfully destroyed!" -ForegroundColor Yellow
Write-Host "==========================================================================" -ForegroundColor Yellow
