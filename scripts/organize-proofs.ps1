# Organize-Proofs.ps1
# Helper script to automatically rename and align screenshots for your DevOps submission.

$ScreenshotsDir = "$PSScriptRoot\..\screenshots"
Set-Location $ScreenshotsDir

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "      *** DevOps Submission Screenshot Organizer ***      " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Looking in directory: $ScreenshotsDir" -ForegroundColor Gray

# 1. Identify date-based screenshots
$RawScreenshots = Get-ChildItem -Filter "Screenshot 2026-05-23 *.png"

if ($RawScreenshots.Count -eq 0) {
    Write-Host "`n[OK] No default dated screenshots found, or they are already organized!" -ForegroundColor Green
    Write-Host "Active organized screenshots in screenshots/:" -ForegroundColor Gray
    Get-ChildItem -Filter "*.png" | Select-Object Name, Length | Format-Table -AutoSize
    Exit
}

Write-Host "`nFound $($RawScreenshots.Count) raw dated screenshots. Let's map them to their README targets!" -ForegroundColor Yellow
Write-Host "----------------------------------------------------------" -ForegroundColor Gray

$Targets = @(
    @{ Name = "vpc-topology.png"; Desc = "AWS Console VPC Resource Map Topology Diagram" },
    @{ Name = "ansible-complete.png"; Desc = "Ansible playbook execution recaps showing 0 failures" },
    @{ Name = "nginx-active.png"; Desc = "Nginx systemctl active (running) status output" },
    @{ Name = "iii-engine-active.png"; Desc = "Central iii-engine broker active (running) status output" },
    @{ Name = "workers-active.png"; Desc = "Private VM worker systemd active (running) status outputs" }
)

$i = 0
foreach ($File in $RawScreenshots) {
    Write-Host "`n[$i] File: $($File.Name) (Size: $([Math]::Round($File.Length / 1KB, 1)) KB)" -ForegroundColor Cyan
    Write-Host "Please select what this screenshot represents:" -ForegroundColor White
    
    for ($j = 0; $j -lt $Targets.Length; $j++) {
        Write-Host "  [$j] $($Targets[$j].Name) -- $($Targets[$j].Desc)" -ForegroundColor Gray
    }
    Write-Host "  [S] Skip this file" -ForegroundColor Yellow
    
    $Choice = Read-Host "Enter choice (0-$($Targets.Length - 1) or S)"
    
    if ($Choice -eq 'S' -or $Choice -eq 's' -or [string]::IsNullOrWhiteSpace($Choice)) {
        Write-Host "Skipped." -ForegroundColor Gray
        continue
    }
      
    $Index = 0
    if ([int]::TryParse($Choice, [ref]$Index)) {
        if ($Index -ge 0 -and $Index -lt $Targets.Length) {
            $TargetName = $Targets[$Index].Name
            if (Test-Path $TargetName) {
                $Confirm = Read-Host "$TargetName already exists. Overwrite? (Y/N)"
                if ($Confirm -ne 'Y' -and $Confirm -ne 'y') {
                    Write-Host "Cancelled overwrite." -ForegroundColor Gray
                    continue
                }
                Remove-Item $TargetName -Force
            }
            Rename-Item -Path $File.FullName -NewName $TargetName
            Write-Host "[OK] Renamed to $TargetName!" -ForegroundColor Green
        } else {
            Write-Host "[!] Index out of range. Skipping." -ForegroundColor Red
        }
    } else {
        Write-Host "[!] Invalid numeric entry. Skipping." -ForegroundColor Red
    }
}

Write-Host "`nAll operations complete!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Cyan
