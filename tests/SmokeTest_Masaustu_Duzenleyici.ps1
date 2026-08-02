#requires -version 5.1
[CmdletBinding()]
param(
    [string]$ScriptPath = (Join-Path $PSScriptRoot '..\Masaustu_Duzenleyici.ps1'),
    [string]$ExePath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

$root = Join-Path $env:TEMP ('deskopt-sorter-test-' + [guid]::NewGuid().ToString('N'))
$source = Join-Path $root 'Desktop'
$destination = Join-Path $root 'Documents'

try {
    New-Item -ItemType Directory -Path $source, $destination -Force | Out-Null

    Set-Content -LiteralPath (Join-Path $source 'note.txt') -Value 'note' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $source 'photo.jpg') -Value 'image' -Encoding UTF8

    $project = Join-Path $source 'ProjectAlpha'
    New-Item -ItemType Directory -Path $project -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $project 'main.py') -Value 'print(1)' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $project 'README.md') -Value '# test' -Encoding UTF8

    $runner = if ([string]::IsNullOrWhiteSpace($ExePath)) { $ScriptPath } else { $ExePath }

    function Invoke-Organizer {
        param([string]$RunMode)

        $args = @(
            '-Mode', $RunMode,
            '-SourceRoot', $source,
            '-DestinationRoot', $destination,
            '-NonInteractive'
        )

        if ([string]::IsNullOrWhiteSpace($ExePath)) {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner @args | Out-Null
        }
        else {
            & $runner @args | Out-Null
        }

        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            throw "Organizer exit code: $LASTEXITCODE ($RunMode)"
        }
    }

    Invoke-Organizer -RunMode 'Preview'
    Assert-True (Test-Path (Join-Path $source 'note.txt')) 'Preview moved note.txt.'
    Assert-True (Test-Path (Join-Path $source 'photo.jpg')) 'Preview moved photo.jpg.'
    Assert-True (Test-Path (Join-Path $source 'ProjectAlpha\main.py')) 'Preview moved project folder.'

    Invoke-Organizer -RunMode 'Move'
    Assert-True (-not (Test-Path (Join-Path $source 'note.txt'))) 'Move left note.txt in source.'
    Assert-True (-not (Test-Path (Join-Path $source 'photo.jpg'))) 'Move left photo.jpg in source.'
    Assert-True (-not (Test-Path (Join-Path $source 'ProjectAlpha'))) 'Move left ProjectAlpha in source.'

    $destinationFiles = @(Get-ChildItem -LiteralPath $destination -File -Recurse -Force)
    Assert-True ($destinationFiles.Name -contains 'note.txt') 'note.txt not found in destination.'
    Assert-True ($destinationFiles.Name -contains 'photo.jpg') 'photo.jpg not found in destination.'
    Assert-True ($destinationFiles.Name -contains 'main.py') 'Project file not found in destination.'

    Invoke-Organizer -RunMode 'UndoLast'
    Assert-True (Test-Path (Join-Path $source 'note.txt')) 'Undo did not restore note.txt.'
    Assert-True (Test-Path (Join-Path $source 'photo.jpg')) 'Undo did not restore photo.jpg.'
    Assert-True (Test-Path (Join-Path $source 'ProjectAlpha\main.py')) 'Undo did not restore project folder.'

    Write-Host 'SMOKE TEST PASSED'
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
