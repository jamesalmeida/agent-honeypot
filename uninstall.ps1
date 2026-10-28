#Requires -Version 5.1
<#
agent-honeypot uninstaller for Windows.

Removes the flag links created by install.ps1. Copies are removed only when
their content still matches the installed flag; anything else is left alone.
The flag and guestbook in the user profile are kept unless -Purge is passed.

Usage:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1 -Purge
#>

[CmdletBinding()]
param(
    [switch]$Purge
)

$ErrorActionPreference = 'Stop'

$homeDir = $env:USERPROFILE
if ([string]::IsNullOrWhiteSpace($homeDir)) {
    $homeDir = [Environment]::GetFolderPath('UserProfile')
}
$flag = Join-Path $homeDir 'flag.txt'
$guest = Join-Path $homeDir 'guest-book.txt'

function Test-SameContent {
    param([string]$A, [string]$B)
    try {
        return (Get-FileHash -LiteralPath $A -Algorithm SHA256).Hash -eq
               (Get-FileHash -LiteralPath $B -Algorithm SHA256).Hash
    } catch {
        return $false
    }
}

$targets = New-Object System.Collections.Generic.List[string]
$targets.Add('C:\flag.txt')
if ($env:ProgramData) { $targets.Add((Join-Path $env:ProgramData 'flag.txt')) }
if ($env:SystemRoot) {
    $targets.Add((Join-Path $env:SystemRoot 'Temp\flag.txt'))
    $targets.Add((Join-Path $env:SystemRoot 'System32\config\systemprofile\flag.txt'))
}
$targets.Add('C:\Users\Public\flag.txt')
if ($env:TEMP) { $targets.Add((Join-Path $env:TEMP 'flag.txt')) }

foreach ($target in $targets) {
    # Test-Path throws on directories the user cannot list (e.g. the SYSTEM
    # profile); skip those instead of aborting the whole loop.
    if (-not (Test-Path -LiteralPath $target -ErrorAction SilentlyContinue)) { continue }
    $item = Get-Item -LiteralPath $target -Force
    if ($item.PSIsContainer -and -not $item.LinkType) {
        Write-Host "~ kept unrelated directory: $target"
    } elseif ($item.LinkType) {
        Remove-Item -LiteralPath $target -Force
        Write-Host "~ removed link: $target"
    } elseif ((Test-Path -LiteralPath $flag) -and (Test-SameContent $target $flag)) {
        Remove-Item -LiteralPath $target -Force
        Write-Host "~ removed copy: $target"
    } else {
        Write-Host "~ kept unrelated file: $target"
    }
}

if ($Purge) {
    foreach ($p in @($flag, $guest)) {
        if (Test-Path -LiteralPath $p -ErrorAction SilentlyContinue) {
            $item = Get-Item -LiteralPath $p -Force
            if (-not $item.PSIsContainer) {
                Remove-Item -LiteralPath $p -Force
                Write-Host "~ purged: $p"
            }
        }
    }
} else {
    Write-Host "~ kept $flag and $guest (use -Purge to delete them)"
}
