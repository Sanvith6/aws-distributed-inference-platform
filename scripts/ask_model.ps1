param(
    [Parameter(Mandatory=$false)]
    [string]$Question
)

if (-not $Question) {
    $Question = Read-Host "Enter your question for the Gemma model"
}

# Ignore self-signed certificate warnings
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

# Build the JSON payload
$body = @{
  messages = @(
    @{ role = "user"; content = $Question }
  )
} | ConvertTo-Json -Depth 5 -Compress

Write-Host "`nThinking... (This may take up to a minute on the AWS CPU)...`n" -ForegroundColor Cyan

try {
    # Send the request
    $response = Invoke-RestMethod `
      -Uri "https://44.202.193.89/v1/chat/completions" `
      -Method Post `
      -ContentType "application/json" `
      -Body $body `
      -TimeoutSec 180

    # Extract and display just the answer content
    if ($null -ne $response.choices -and $response.choices.Count -gt 0) {
        Write-Host "--- AI RESPONSE ---" -ForegroundColor Green
        Write-Host $response.choices[0].message.content
        Write-Host "-------------------`n" -ForegroundColor Green
    } else {
        Write-Host "Received an unexpected response format:" -ForegroundColor Yellow
        $response | ConvertTo-Json -Depth 5
    }
}
catch {
    Write-Host "An error occurred while contacting the model:`n$($_.Exception.Message)" -ForegroundColor Red
}