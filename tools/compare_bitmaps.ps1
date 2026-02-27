<#
.SYNOPSIS
    Compare two BMP images pixel-by-pixel for FPC vs Delphi rendering verification.

.DESCRIPTION
    Compares reference (Delphi) and test (FPC) BMP files, computing:
    - Per-pixel RGB difference
    - Max difference, mean difference
    - Percentage of pixels above threshold
    - Generates a visual diff image

.PARAMETER RefBmp
    Path to reference (Delphi) BMP file

.PARAMETER TestBmp
    Path to test (FPC) BMP file

.PARAMETER Threshold
    Maximum acceptable mean difference (0-255). Default: 5 (roughly 2%)

.PARAMETER OutputDir
    Directory for diff image and report. Default: same as TestBmp

.EXAMPLE
    .\compare_bitmaps.ps1 -RefBmp ref_default.bmp -TestBmp fpc_default.bmp
    .\compare_bitmaps.ps1 -RefBmp ref\*.bmp -TestBmp fpc\*.bmp -Threshold 3
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$RefBmp,

    [Parameter(Mandatory=$true)]
    [string]$TestBmp,

    [int]$Threshold = 5,

    [string]$OutputDir = ""
)

Add-Type -AssemblyName System.Drawing

function Compare-SinglePair {
    param(
        [string]$RefPath,
        [string]$TestPath,
        [int]$Threshold,
        [string]$OutDir
    )

    if (-not (Test-Path $RefPath)) {
        Write-Host "ERROR: Reference file not found: $RefPath" -ForegroundColor Red
        return $null
    }
    if (-not (Test-Path $TestPath)) {
        Write-Host "ERROR: Test file not found: $TestPath" -ForegroundColor Red
        return $null
    }

    $refImg = [System.Drawing.Bitmap]::new($RefPath)
    $testImg = [System.Drawing.Bitmap]::new($TestPath)

    $refName = [System.IO.Path]::GetFileNameWithoutExtension($RefPath)
    $testName = [System.IO.Path]::GetFileNameWithoutExtension($TestPath)

    Write-Host "`n=== Comparing: $refName vs $testName ===" -ForegroundColor Cyan

    # Check dimensions
    if ($refImg.Width -ne $testImg.Width -or $refImg.Height -ne $testImg.Height) {
        Write-Host "  DIMENSION MISMATCH: Ref=${refImg.Width}x${refImg.Height} Test=${testImg.Width}x${testImg.Height}" -ForegroundColor Red
        $refImg.Dispose()
        $testImg.Dispose()
        return @{
            Name = $testName
            Match = $false
            Reason = "Dimension mismatch"
        }
    }

    $w = $refImg.Width
    $h = $refImg.Height
    $totalPixels = $w * $h

    Write-Host "  Size: ${w}x${h} ($totalPixels pixels)"

    # Create diff image
    $diffImg = [System.Drawing.Bitmap]::new($w, $h)

    $totalDiff = [double]0
    $maxDiff = 0
    $pixelsAboveThreshold = 0
    $exactMatch = 0
    $channelDiffs = @{ R = [double]0; G = [double]0; B = [double]0 }

    for ($y = 0; $y -lt $h; $y++) {
        for ($x = 0; $x -lt $w; $x++) {
            $refPx = $refImg.GetPixel($x, $y)
            $testPx = $testImg.GetPixel($x, $y)

            $dr = [Math]::Abs([int]$refPx.R - [int]$testPx.R)
            $dg = [Math]::Abs([int]$refPx.G - [int]$testPx.G)
            $db = [Math]::Abs([int]$refPx.B - [int]$testPx.B)

            $pixDiff = [Math]::Max($dr, [Math]::Max($dg, $db))

            $channelDiffs.R += $dr
            $channelDiffs.G += $dg
            $channelDiffs.B += $db

            $totalDiff += ($dr + $dg + $db) / 3.0

            if ($pixDiff -gt $maxDiff) { $maxDiff = $pixDiff }
            if ($pixDiff -gt $Threshold) { $pixelsAboveThreshold++ }
            if ($pixDiff -eq 0) { $exactMatch++ }

            # Diff image: amplify differences 10x, show in red-hot colormap
            $amplified = [Math]::Min(255, $pixDiff * 10)
            if ($pixDiff -eq 0) {
                $diffImg.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(0, 0, 0))
            } elseif ($amplified -lt 128) {
                $diffImg.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($amplified * 2, $amplified, 0))
            } else {
                $diffImg.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, 255 - ($amplified - 128) * 2, 0))
            }
        }

        # Progress
        if ($y % 50 -eq 0 -and $y -gt 0) {
            $pct = [Math]::Round(100.0 * $y / $h, 0)
            Write-Host "  Progress: $pct%" -NoNewline
            Write-Host "`r" -NoNewline
        }
    }

    $meanDiff = $totalDiff / $totalPixels
    $pctAbove = 100.0 * $pixelsAboveThreshold / $totalPixels
    $pctExact = 100.0 * $exactMatch / $totalPixels
    $meanR = $channelDiffs.R / $totalPixels
    $meanG = $channelDiffs.G / $totalPixels
    $meanB = $channelDiffs.B / $totalPixels

    # Save diff image
    $diffPath = Join-Path $OutDir "diff_${testName}.bmp"
    $diffImg.Save($diffPath, [System.Drawing.Imaging.ImageFormat]::Bmp)

    # Results
    $pass = $meanDiff -le $Threshold
    $status = if ($pass) { "PASS" } else { "FAIL" }
    $color = if ($pass) { "Green" } else { "Red" }

    Write-Host ""
    Write-Host "  Result: $status" -ForegroundColor $color
    Write-Host "  Mean difference:    $([Math]::Round($meanDiff, 4))"
    Write-Host "  Max difference:     $maxDiff"
    Write-Host "  Mean R/G/B:         $([Math]::Round($meanR, 2)) / $([Math]::Round($meanG, 2)) / $([Math]::Round($meanB, 2))"
    Write-Host "  Exact match pixels: $([Math]::Round($pctExact, 2))%"
    Write-Host "  Pixels > threshold: $([Math]::Round($pctAbove, 2))% ($pixelsAboveThreshold/$totalPixels)"
    Write-Host "  Diff image saved:   $diffPath"

    $refImg.Dispose()
    $testImg.Dispose()
    $diffImg.Dispose()

    return @{
        Name = $testName
        Match = $pass
        MeanDiff = [Math]::Round($meanDiff, 4)
        MaxDiff = $maxDiff
        PctExact = [Math]::Round($pctExact, 2)
        PctAbove = [Math]::Round($pctAbove, 2)
        MeanR = [Math]::Round($meanR, 2)
        MeanG = [Math]::Round($meanG, 2)
        MeanB = [Math]::Round($meanB, 2)
    }
}

# Main
if ($OutputDir -eq "") {
    $OutputDir = Split-Path $TestBmp -Parent
    if ($OutputDir -eq "") { $OutputDir = "." }
}

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Handle wildcards
$refFiles = Get-ChildItem -Path $RefBmp -ErrorAction SilentlyContinue
$testFiles = Get-ChildItem -Path $TestBmp -ErrorAction SilentlyContinue

if ($null -eq $refFiles -or $refFiles.Count -eq 0) {
    Write-Host "No reference files found matching: $RefBmp" -ForegroundColor Red
    exit 1
}

$results = @()

if ($refFiles.Count -eq 1 -and $testFiles.Count -eq 1) {
    # Single pair
    $r = Compare-SinglePair -RefPath $refFiles[0].FullName -TestPath $testFiles[0].FullName -Threshold $Threshold -OutDir $OutputDir
    if ($null -ne $r) { $results += $r }
} else {
    # Match by scene name: ref_XXX.bmp <-> fpc_XXX.bmp
    foreach ($refFile in $refFiles) {
        $sceneName = $refFile.BaseName -replace '^ref_', ''
        $testFile = $testFiles | Where-Object { $_.BaseName -replace '^fpc_', '' -eq $sceneName } | Select-Object -First 1

        if ($null -ne $testFile) {
            $r = Compare-SinglePair -RefPath $refFile.FullName -TestPath $testFile.FullName -Threshold $Threshold -OutDir $OutputDir
            if ($null -ne $r) { $results += $r }
        } else {
            Write-Host "`nWARNING: No matching FPC file for ref scene '$sceneName'" -ForegroundColor Yellow
        }
    }
}

# Summary
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

$passCount = ($results | Where-Object { $_.Match }).Count
$failCount = ($results | Where-Object { -not $_.Match }).Count

foreach ($r in $results) {
    $icon = if ($r.Match) { "[PASS]" } else { "[FAIL]" }
    $color = if ($r.Match) { "Green" } else { "Red" }
    Write-Host ("  {0} {1,-30} mean={2,8} max={3,4} exact={4,7}%" -f $icon, $r.Name, $r.MeanDiff, $r.MaxDiff, $r.PctExact) -ForegroundColor $color
}

Write-Host ""
Write-Host "  Total: $($results.Count) comparisons, $passCount passed, $failCount failed" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Red" })
Write-Host "  Threshold: mean diff <= $Threshold" -ForegroundColor Gray

# Save report
$reportPath = Join-Path $OutputDir "comparison_report.txt"
$report = @()
$report += "FPC vs Delphi Pixel Comparison Report"
$report += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$report += "Threshold: mean diff <= $Threshold"
$report += ""

foreach ($r in $results) {
    $icon = if ($r.Match) { "PASS" } else { "FAIL" }
    $report += "[$icon] $($r.Name)"
    $report += "  Mean diff: $($r.MeanDiff)  Max diff: $($r.MaxDiff)"
    $report += "  Mean R/G/B: $($r.MeanR) / $($r.MeanG) / $($r.MeanB)"
    $report += "  Exact match: $($r.PctExact)%  Above threshold: $($r.PctAbove)%"
    $report += ""
}

$report += "Total: $($results.Count) comparisons, $passCount passed, $failCount failed"
$report | Out-File -FilePath $reportPath -Encoding utf8

Write-Host "  Report saved: $reportPath" -ForegroundColor Gray

# Exit code
if ($failCount -gt 0) { exit 1 } else { exit 0 }
