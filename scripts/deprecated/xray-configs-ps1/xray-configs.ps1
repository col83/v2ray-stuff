# =============================================================================
# CONFIGURATION - Edit these constants to change filenames
# =============================================================================
$CONFIG_FILENAME_SOURCES    = "sources.txt"
$CONFIG_FILENAME_COUNTRIES  = "filter-countries.txt"
$CONFIG_FILENAME_TRANSPORT  = "filter-transport.txt"
$OUTPUT_FILENAME_FALLBACK   = "output.txt"
# =============================================================================

# Set encoding (PowerShell 5.1 friendly)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$ErrorActionPreference = "Stop"

# Cross-version determination of script directory
$ScriptDir = if ($PSScriptRoot) {
    $PSScriptRoot
}
else {
    Split-Path -Parent $MyInvocation.MyCommand.Definition
}

# Build full paths using the constants defined above
$SourcesFile   = Join-Path $ScriptDir $CONFIG_FILENAME_SOURCES
$CountriesFile = Join-Path $ScriptDir $CONFIG_FILENAME_COUNTRIES
$TransportFile = Join-Path $ScriptDir $CONFIG_FILENAME_TRANSPORT
$OutputFile    = Join-Path $ScriptDir $OUTPUT_FILENAME_FALLBACK

# Helper function: Validate that a required config file exists
function Test-ConfigFile {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [Parameter(Mandatory)]
        [string]$Description
    )
    
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $fileName = Split-Path -Path $Path -Leaf
        $errMsg = "Configuration file not found: '$fileName'`n"
        $errMsg += "Description: $Description`n"
        $errMsg += "Expected location: $Path`n`n"
        $errMsg += "Please create the file and add valid entries (one per line, # for comments)."
        throw $errMsg
    }
}

function Read-ConfigLines {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Configuration file not found: $Path"
    }

    $lines = Get-Content -LiteralPath $Path -Encoding UTF8 |
        ForEach-Object {
            $_.Trim()
        } |
        Where-Object {
            $_ -and -not $_.StartsWith("#")
        }

    return $lines
}

function Get-SubscriptionContent {
    param(
        [Parameter(Mandatory)]
        [string[]]$Urls
    )

    $result = [System.Collections.Generic.List[string]]::new()

    $userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"

    if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
        throw "curl.exe not found. Requires Windows 10/11 or standalone cURL."
    }

    foreach ($url in $Urls) {

        if ($url -notmatch '^https?://') {
            Write-Warning "Skipping invalid URL format: $url"
            continue
        }

        Write-Host "[INFO] Fetching $url"

        try {

            [string]$content = & curl.exe `
                -s `
                -L `
                -f `
                --max-time 20 `
                --compressed `
                -A $userAgent `
                $url 2>$null

            if ($LASTEXITCODE -ne 0) {
                Write-Warning "curl.exe failed for $url (exit code: $LASTEXITCODE)"
                continue
            }

            # Check for null or whitespace content
            if (-not $content -or [string]::IsNullOrWhiteSpace($content)) {
                Write-Warning "Empty response: $url"
                continue
            }

            # Normalize line endings (remove CR)
            $content = $content -replace "`r", ""

            # Try standard split by newline
            $lines = @(
                $content -split "`n" |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_ }
            )

            # If we got a single large string, try to extract URIs using regex
            if ($lines.Count -le 1) {

                # Pattern matches proxy URIs: vless://, vmess://, trojan://, ss://
                # Uses lookahead to split on next protocol or end of string
                $uriMatches = [regex]::Matches(
                    $content,
                    '(vless|vmess|trojan|ss)://.*?(?=(vless|vmess|trojan|ss)://|$)',
                    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
                )

                if ($uriMatches.Count -gt 0) {

                    foreach ($m in $uriMatches) {

                        $line = $m.Value.Trim()

                        if ($line) {
                            $result.Add($line)
                        }
                    }

                    continue
                }
            }

            # Add standard lines
            foreach ($line in $lines) {

                if ($line) {
                    $result.Add($line)
                }
            }
        }
        catch {
            Write-Warning "Failed to fetch: $url ($($_.Exception.Message))"
        }
    }

    return $result.ToArray()
}

function Filter-ByCountries {
    param(
        [Parameter(Mandatory)]
        [string[]]$Lines,

        [string[]]$Countries
    )

    if (-not $Lines -or $Lines.Count -eq 0) {
        return @()
    }

    if (-not $Countries -or $Countries.Count -eq 0) {
        return $Lines
    }

    $escaped = $Countries | ForEach-Object {
        [regex]::Escape($_)
    }

    # Search for countries in tag/comment part of URI (# or %23 encoded)
    $pattern = '(?i)(#|%23).*(' + ($escaped -join '|') + ')'

    $matched = @(
        $Lines | Where-Object {
            $_ -match $pattern
        }
    )

    return $matched
}

function Filter-ByTransport {
    param(
        [Parameter(Mandatory)]
        [string[]]$Lines,

        [string[]]$AllowedTransport
    )

    if (-not $Lines -or $Lines.Count -eq 0) {
        return @()
    }

    if (-not $AllowedTransport -or $AllowedTransport.Count -eq 0) {
        return $Lines
    }

    $escaped = $AllowedTransport | ForEach-Object {
        [regex]::Escape($_)
    }

    # Search for transport/security/network/mode parameters in URI query string
    $pattern = '(?i)(type|security|network|mode)=(' +
               ($escaped -join '|') +
               ')'

    $regex = [regex]::new(
        $pattern,
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    $matched = @(
        $Lines | Where-Object {
            $regex.IsMatch($_)
        }
    )

    return $matched
}

try {

    Write-Host "[INFO] Loading configuration files"

    # Validate all required config files exist BEFORE attempting to read them
    Test-ConfigFile -Path $SourcesFile -Description "List of subscription URLs to fetch (one per line)"
    Test-ConfigFile -Path $CountriesFile -Description "List of country codes/names to filter by (e.g., RU, DE, US)"
    Test-ConfigFile -Path $TransportFile -Description "List of allowed transport types (e.g., tcp, ws, grpc)"

    $Sources   = Read-ConfigLines -Path $SourcesFile
    $Countries = Read-ConfigLines -Path $CountriesFile
    $Transport = Read-ConfigLines -Path $TransportFile

    if ($Sources.Count -eq 0) {
        throw "Configuration file '$CONFIG_FILENAME_SOURCES' is empty or contains no valid URLs"
    }

    Write-Host "[INFO] Fetching subscriptions"

    $RawLines = Get-SubscriptionContent -Urls $Sources

    Write-Host "[DEBUG] Fetched $($RawLines.Count) raw lines"

    if ($RawLines.Count -eq 0) {
        throw "No valid subscription lines fetched from any source"
    }

    Write-Host "[INFO] Applying country filter"

    $Filtered = Filter-ByCountries `
        -Lines $RawLines `
        -Countries $Countries

    Write-Host "[DEBUG] After country filter: $($Filtered.Count) lines"

    Write-Host "[INFO] Applying transport filter"

    $Filtered = Filter-ByTransport `
        -Lines $Filtered `
        -AllowedTransport $Transport

    Write-Host "[DEBUG] After transport filter: $($Filtered.Count) lines"

    # Remove duplicates
    $Filtered = @(
        $Filtered |
        Sort-Object -Unique
    )

    if ($Filtered.Count -eq 0) {
        Write-Warning "No matching lines found after filtering"
        exit 0
    }

    try {

        $clipText = $Filtered -join "`r`n"

        Add-Type -AssemblyName System.Windows.Forms

        [System.Windows.Forms.Clipboard]::SetText($clipText)

        Write-Host ""
        Write-Host "[OK] Copied $($Filtered.Count) unique lines to clipboard" -ForegroundColor Green
        Write-Host ""
    }
    catch {

        Write-Warning "Clipboard copy failed: $($_.Exception.Message)"
        Write-Host "[INFO] Falling back to file output..."

        $Filtered |
            Out-File `
                -FilePath $OutputFile `
                -Encoding UTF8 `
                -Force

        Write-Host ""
        Write-Host "[OK] Saved $($Filtered.Count) unique lines to $OutputFile" -ForegroundColor Yellow
        Write-Host ""
    }
}
catch {

    Write-Host "" -ForegroundColor Red
    Write-Host "[ERROR] Script execution failed" -ForegroundColor Red
    Write-Host "==========================================" -ForegroundColor Red
    Write-Host "" -ForegroundColor Red
    
    Write-Host "Message: $($_.Exception.Message)" -ForegroundColor Red

    if ($_.InvocationInfo.ScriptLineNumber) {
        Write-Host "Location: Line $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Yellow
    }
    
    Write-Host "" -ForegroundColor Red
    Write-Host "Troubleshooting tips:" -ForegroundColor Cyan
    Write-Host "  1. Check that all configuration files exist in: $ScriptDir" -ForegroundColor Cyan
    Write-Host "  2. Ensure files are encoded in UTF-8 without BOM" -ForegroundColor Cyan
    Write-Host "  3. Verify URLs in sources.txt are accessible" -ForegroundColor Cyan
    Write-Host "" -ForegroundColor Red

    exit 1
}