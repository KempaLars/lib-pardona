<#
.SYNOPSIS
    Installs the LibPardonaTest addon (with the current library checkout) into the WoW Forever AddOns
    folder, or into another AddOns folder given with -AddOnsPath.

.DESCRIPTION
    Without parameters the default path is used:
        C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns
    Pass -AddOnsPath only for a different installation.

    - Deletes only <AddOnsPath>\LibPardonaTest if it exists.
    - Copies tools\LibPardonaTest\* to <AddOnsPath>\LibPardonaTest.
    - Copies lib-pardona.xml, LibStub\ and LibPardona-1.0\ to
      <AddOnsPath>\LibPardonaTest\Libs\lib-pardona\.

    If deleting or copying fails with "access denied" (e.g. below Program Files), the script stops with a
    hint to run PowerShell as administrator or to check the write permissions of the WoW folder.

.PARAMETER AddOnsPath
    Path to Interface\AddOns. Optional; defaults to the WoW Forever installation in Program Files (x86).

.EXAMPLE
    .\tools\install-test.ps1

.EXAMPLE
    .\tools\install-test.ps1 -AddOnsPath "D:\Games\World of Warcraft\_forever_\Interface\AddOns"
#>
[CmdletBinding()]
param(
    [string]$AddOnsPath = 'C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns'
)

$ErrorActionPreference = 'Stop'

# Runs one delete/copy step; "access denied" ends the script with a clear message.
function Invoke-InstallStep {
    param([scriptblock]$Step)
    try {
        & $Step
    } catch {
        $err = $_
        $denied = $err.CategoryInfo.Category -eq 'PermissionDenied'
        $ex = $err.Exception
        while ($ex -and -not $denied) {
            if ($ex -is [System.UnauthorizedAccessException]) { $denied = $true }
            $ex = $ex.InnerException
        }
        if ($denied) {
            Write-Error -ErrorAction Continue ("Access denied: " + $err.Exception.Message)
            throw ("Cannot write to '$AddOnsPath'. Start PowerShell as administrator " +
                "or check the write permissions for the WoW folder.")
        }
        throw
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceAddon = Join-Path $repoRoot 'tools\LibPardonaTest'

if (-not (Test-Path -LiteralPath $AddOnsPath -PathType Container)) {
    throw "AddOns path not found: $AddOnsPath (use -AddOnsPath for a different installation)"
}
if (-not (Test-Path -LiteralPath $sourceAddon -PathType Container)) {
    throw "Test addon sources not found: $sourceAddon"
}

$addOnsFull = (Resolve-Path -LiteralPath $AddOnsPath).Path
$target = Join-Path $addOnsFull 'LibPardonaTest'
$libTarget = Join-Path $target 'Libs\lib-pardona'

# Remove only the test addon folder itself
if (Test-Path -LiteralPath $target) {
    Invoke-InstallStep { Remove-Item -LiteralPath $target -Recurse -Force }
    Write-Host "Removed old $target"
}

Invoke-InstallStep {
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Copy-Item -Path (Join-Path $sourceAddon '*') -Destination $target -Recurse -Force

    New-Item -ItemType Directory -Path $libTarget -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot 'lib-pardona.xml') -Destination $libTarget -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot 'LibStub') -Destination $libTarget -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot 'LibPardona-1.0') -Destination $libTarget -Recurse -Force
}

Write-Host "Installed LibPardonaTest to $target"
Write-Host "Copied files:"
Get-ChildItem -LiteralPath $target -Recurse -File | ForEach-Object {
    Write-Host ("  " + $_.FullName.Substring($target.Length + 1))
}
