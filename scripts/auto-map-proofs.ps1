# auto-map-proofs.ps1
# Automates screenshot alignment by checking the exact dated files in screenshots/ and renaming them non-interactively.

$ScreenshotsDir = "$PSScriptRoot\..\screenshots"
Set-Location $ScreenshotsDir

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "    [Robot] Non-Interactive DevOps Screenshot Organizer   " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Define mappings based on your actual timestamps
$Mappings = @(
    @{ Src = "Screenshot 2026-05-23 001709.png"; Dests = @("vpc-topology.png") },
    @{ Src = "Screenshot 2026-05-23 001844.png"; Dests = @("ansible-complete.png") },
    @{ Src = "Screenshot 2026-05-23 001933.png"; Dests = @("nginx-active.png", "iii-engine-active.png") },
    @{ Src = "Screenshot 2026-05-23 002107.png"; Dests = @("completions-curl.png") }
)

$SuccessCount = 0

foreach ($Map in $Mappings) {
    $SrcFile = $Map.Src
    if (Test-Path $SrcFile) {
        $PrimaryDest = $Map.Dests[0]
        # Rename original to primary target
        Rename-Item -Path $SrcFile -NewName $PrimaryDest -Force
        Write-Host "[OK] Aligned $SrcFile -> $PrimaryDest" -ForegroundColor Green
        $SuccessCount++
        
        # If there are additional target copies (e.g. sharing Nginx / Engine active printout)
        if ($Map.Dests.Count -gt 1) {
            for ($j = 1; $j -lt $Map.Dests.Count; $j++) {
                $ExtraDest = $Map.Dests[$j]
                Copy-Item -Path $PrimaryDest -Destination $ExtraDest -Force
                Write-Host "[OK] Copied  $PrimaryDest -> $ExtraDest" -ForegroundColor Green
            }
        }
    } else {
        Write-Host "[-] Source $SrcFile not found. Skipping." -ForegroundColor Gray
    }
}

if ($SuccessCount -gt 0) {
    Write-Host "`n[OK] Successfully organized $SuccessCount dated screenshots!" -ForegroundColor Green
} else {
    Write-Host "`n[i] No unorganized dated screenshots found. They may already be aligned." -ForegroundColor Yellow
}

Write-Host "`nActive submission screenshots in screenshots/:" -ForegroundColor Gray
Get-ChildItem -Filter "*.png" | Select-Object Name, Length | Format-Table -AutoSize
Write-Host "==========================================================" -ForegroundColor Cyan
