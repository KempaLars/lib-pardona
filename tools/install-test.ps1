<#
.SYNOPSIS
    Installs the LibPardonaTest addon (with the current library checkout) into a WoW AddOns folder.

.DESCRIPTION
    - Deletes only <AddOnsPath>\LibPardonaTest if it exists.
    - Copies tools\LibPardonaTest\* to <AddOnsPath>\LibPardonaTest.
    - Copies lib-pardona.xml, LibStub\ and LibPardona-1.0\ to
      <AddOnsPath>\LibPardonaTest\Libs\lib-pardona\.

.EXAMPLE
    .\tools\install-test.ps1 -AddOnsPath "C:\Games\World of Warcraft\_retail_\Interface\AddOns"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$AddOnsPath
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceAddon = Join-Path $repoRoot 'tools\LibPardonaTest'

if (-not (Test-Path -LiteralPath $AddOnsPath -PathType Container)) {
    throw "AddOns path not found: $AddOnsPath"
}
if (-not (Test-Path -LiteralPath $sourceAddon -PathType Container)) {
    throw "Test addon sources not found: $sourceAddon"
}

$addOnsFull = (Resolve-Path -LiteralPath $AddOnsPath).Path
$target = Join-Path $addOnsFull 'LibPardonaTest'
$libTarget = Join-Path $target 'Libs\lib-pardona'

# Remove only the test addon folder itself
if (Test-Path -LiteralPath $target) {
    Remove-Item -LiteralPath $target -Recurse -Force
    Write-Host "Removed old $target"
}

New-Item -ItemType Directory -Path $target -Force | Out-Null
Copy-Item -Path (Join-Path $sourceAddon '*') -Destination $target -Recurse -Force

New-Item -ItemType Directory -Path $libTarget -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot 'lib-pardona.xml') -Destination $libTarget -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'LibStub') -Destination $libTarget -Recurse -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'LibPardona-1.0') -Destination $libTarget -Recurse -Force

Write-Host "Installed LibPardonaTest to $target"
Write-Host "Copied files:"
Get-ChildItem -LiteralPath $target -Recurse -File | ForEach-Object {
    Write-Host ("  " + $_.FullName.Substring($target.Length + 1))
}
