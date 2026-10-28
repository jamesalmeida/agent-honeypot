#Requires -Version 5.1
<#
agent-honeypot installer for Windows.

Drops a safety checkpoint flag and an append-only guestbook in the invoking
user's profile, and links the flag into common places a visitor checks.

Symlinks require Administrator or Developer Mode. Without that privilege the
script falls back to copies and says so.

Usage:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Force
#>

[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$homeDir = $env:USERPROFILE
if ([string]::IsNullOrWhiteSpace($homeDir)) {
    $homeDir = [Environment]::GetFolderPath('UserProfile')
}
if ([string]::IsNullOrWhiteSpace($homeDir)) {
    throw 'Could not determine the user profile directory.'
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

function Test-IsReparseOrDirectory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue)) {
        return $false
    }
    $item = Get-Item -LiteralPath $Path -Force
    return [bool]($item.LinkType -or $item.PSIsContainer -or ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint))
}

if (Test-IsReparseOrDirectory $flag) {
    throw "Refusing to operate on symlink, reparse point, or directory at: $flag"
}
if (Test-IsReparseOrDirectory $guest) {
    throw "Refusing to operate on symlink, reparse point, or directory at: $guest"
}

# --- flag ---------------------------------------------------------------
if ((Test-Path -LiteralPath $flag) -and -not $Force) {
    Write-Host "~ flag already exists, leaving it alone (use -Force to replace): $flag"
} else {
    Copy-Item -LiteralPath (Join-Path $scriptDir 'flag.txt') -Destination $flag -Force
    Write-Host "~ installed flag: $flag"
}

# --- guestbook ----------------------------------------------------------
if (Test-Path -LiteralPath $guest) {
    Write-Host "~ guestbook already exists, keeping existing entries: $guest"
} else {
    Copy-Item -LiteralPath (Join-Path $scriptDir 'guest-book.txt') -Destination $guest -Force
    Write-Host "~ created guestbook: $guest"
}

# Make the flag readable so a visitor running as another local user can read it.
# The guestbook keeps default user-profile permissions (owner-writable) to prevent
# local disk-exhaustion DoS, tampering, or deletion by other accounts.
try {
    if (-not (Test-IsReparseOrDirectory $flag)) {
        $sid = New-Object -TypeName System.Security.Principal.SecurityIdentifier -ArgumentList ([System.Security.Principal.WellKnownSidType]::WorldSid), $null
        $rule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $sid, 'Read', 'Allow'
        $acl = Get-Acl -LiteralPath $flag
        $acl.SetAccessRule($rule)
        Set-Acl -LiteralPath $flag -AclObject $acl
    }
} catch {
    Write-Warning "could not widen flag permissions: $_"
}

# --- links --------------------------------------------------------------
$targets = New-Object System.Collections.Generic.List[string]
$targets.Add('C:\flag.txt')
if ($env:ProgramData) { $targets.Add((Join-Path $env:ProgramData 'flag.txt')) }
if ($env:SystemRoot) {
    $targets.Add((Join-Path $env:SystemRoot 'Temp\flag.txt'))
    $targets.Add((Join-Path $env:SystemRoot 'System32\config\systemprofile\flag.txt'))
}
$targets.Add('C:\Users\Public\flag.txt')
if ($env:TEMP) { $targets.Add((Join-Path $env:TEMP 'flag.txt')) }

$linked = 0
$copied = 0
foreach ($target in $targets) {
    $parent = Split-Path -Parent $target
    # Test-Path throws on directories the user cannot list (e.g. the SYSTEM
    # profile); treat those as absent instead of aborting the whole loop.
    if (-not (Test-Path -LiteralPath $parent -ErrorAction SilentlyContinue)) {
        Write-Host "~ skipped (missing or inaccessible parent): $target"
        continue
    }

    if (Test-Path -LiteralPath $target -ErrorAction SilentlyContinue) {
        $item = Get-Item -LiteralPath $target -Force
        if ($item.PSIsContainer -and -not $item.LinkType) {
            Write-Host "~ skipped (target is a directory): $target"
            continue
        }
        if ($item.LinkType) {
            Remove-Item -LiteralPath $target -Force
        } elseif ($Force -or (Test-SameContent $target $flag)) {
            Remove-Item -LiteralPath $target -Force
        } else {
            Write-Host "~ kept existing non-link file: $target (use -Force to replace)"
            continue
        }
    }

    try {
        New-Item -ItemType SymbolicLink -Path $target -Target $flag -Force | Out-Null
        Write-Host "~ linked: $target -> $flag"
        $linked++
    } catch {
        try {
            Copy-Item -LiteralPath $flag -Destination $target -Force
            Write-Host "~ copied (no symlink privilege): $target"
            $copied++
        } catch {
            Write-Warning "could not place ${target}: $_"
        }
    }
}

Write-Host ''
Write-Host "Done. Linked: $linked, copied: $copied"
if ($copied -gt 0) {
    Write-Host 'Copies do not track edits to the flag; re-run this script after changing it.'
}
Write-Host "Signatures go to: $guest"
Write-Host "Read them with: Get-Content -LiteralPath '$guest'"
