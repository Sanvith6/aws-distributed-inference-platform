# PowerShell Test Script to send an inference request to the API Gateway
$ErrorActionPreference = "Stop"

Push-Location terraform
$enginePubIp = (terraform output -raw engine_public_ip).Trim()
Pop-Location

Write-Host "[*] Sending inference request to https://$enginePubIp/v1/chat/completions..." -ForegroundColor Cyan

# Trust all self-signed certificates
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

$body = @{
    messages = @(
        [ordered]@{ role = "system"; content = "You are a helpful assistant." }
        [ordered]@{ role = "user"; content = "What is 2+2?" }
    )
} | ConvertTo-Json -Depth 4

try {
    $res = Invoke-RestMethod -Uri "https://$enginePubIp/v1/chat/completions" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 120
    $res | ConvertTo-Json -Depth 10 | Write-Host
} catch {
    Write-Host "[-] Request failed: $_" -ForegroundColor Red
}
