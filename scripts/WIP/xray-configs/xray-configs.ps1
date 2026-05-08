
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$SourcesFile   = Join-Path $ScriptDir "sources.txt"
$CountriesFile = Join-Path $ScriptDir "filter-countries.txt"
$TransportFile = Join-Path $ScriptDir "filter-transport.txt"

function Read-ConfigLines {
    param(
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        Write-Host "[ERROR] File not found: $Path"
        exit 1
    }

    Get-Content $Path -Encoding UTF8 |
        ForEach-Object { $_.Trim() } |
        Where-Object {
            $_ -and
            -not $_.StartsWith("#")
        }
}

function Get-SubscriptionContent {
    param(
        [string[]]$Urls
    )

    $result = @()

    foreach ($url in $Urls) {

        Write-Host "[INFO] Fetching $url"

        try {
            $content = (Invoke-WebRequest -Uri $url -UseBasicParsing).Content

            if ($content) {
                $result += ($content -split "`n")
            }
        }
        catch {
            Write-Host "[WARN] Failed: $url"
        }
    }

    return $result
}

function Filter-ByCountries {
    param(
        [string[]]$Lines,
        [string[]]$Countries
    )

    if ($Countries.Count -eq 0) {
        return $Lines
    }

    $pattern = ($Countries | ForEach-Object {
        [regex]::Escape($_)
    }) -join "|"

    return $Lines | Where-Object {
        $_ -match $pattern
    }
}

function Filter-ByTransport {
    param(
        [string[]]$Lines,
        [string[]]$AllowedTransport
    )

    if ($AllowedTransport.Count -eq 0) {
        return $Lines
    }

    return $Lines | Where-Object {

        foreach ($transport in $AllowedTransport) {

            if ($_ -match "type=$([regex]::Escape($transport))") {
                return $true
            }
        }

        return $false
    }
}

# LOAD CONFIGS
$Sources   = Read-ConfigLines $SourcesFile
$Countries = Read-ConfigLines $CountriesFile
$Transport = Read-ConfigLines $TransportFile

# FETCH
$RawLines = Get-SubscriptionContent $Sources

# FILTERS
$Filtered = Filter-ByCountries `
    -Lines $RawLines `
    -Countries $Countries

$Filtered = Filter-ByTransport `
    -Lines $Filtered `
    -AllowedTransport $Transport

# OUTPUT
$Filtered |
    Sort-Object -Unique |
    Set-Clipboard

Write-Host ""
Write-Host "[OK] Copied $($Filtered.Count) lines to clipboard"
Write-Host ""