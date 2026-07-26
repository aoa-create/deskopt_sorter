[CmdletBinding()]
param(
    [ValidateSet("Preview", "Apply")]
    [string]$Mode = "Preview",

    [string]$DocumentsRoot = (Join-Path $env:USERPROFILE "Documents")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Bu betik yalnız DocumentsRoot altındaki açıkça tanımlanmış alanları yönetir.
$DocumentsRoot = [IO.Path]::GetFullPath($DocumentsRoot).TrimEnd("\")
$ProjectArchive = Join-Path $DocumentsRoot "PROJE_ARSIVI"
$GitHubRoot = Join-Path $DocumentsRoot "GitHub_Projeleri"
$FileArchive = Join-Path $DocumentsRoot "DOSYA_KOKENLI_ARSIV"
$CentralLogRoot = Join-Path $DocumentsRoot "_BELGELER_DUZENLEME_KAYITLARI"
$DesktopOrganized = Join-Path $DocumentsRoot "Masaustu_Duzenlenmis"
$DesktopApp = Join-Path $DocumentsRoot "Masaustu_Duzenleyici_Uygulamasi"

$script:Journal = [Collections.Generic.List[object]]::new()

function Assert-InScope {
    param([Parameter(Mandatory)][string]$Path)

    $full = [IO.Path]::GetFullPath($Path).TrimEnd("\")
    $prefix = $DocumentsRoot + "\"
    if (-not $full.StartsWith(
        $prefix,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Belgeler dışındaki hedef reddedildi: $full"
    }
    if ($full.Equals(
        $DocumentsRoot,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Belgeler kökü işlem hedefi olamaz."
    }
}

function Add-Journal {
    param(
        [string]$Action,
        [string]$Source,
        [string]$Destination = "",
        [long]$Files = 0,
        [long]$Bytes = 0,
        [string]$Status = "Planned",
        [string]$Note = ""
    )

    $script:Journal.Add([pscustomobject]@{
        Timestamp = (Get-Date).ToString("o")
        Action = $Action
        Source = $Source
        Destination = $Destination
        Files = $Files
        Bytes = $Bytes
        Status = $Status
        Note = $Note
    })
}

function Get-TreeStats {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Files = 0L; Bytes = 0L; Directories = 0L }
    }

    $item = Get-Item -LiteralPath $Path -Force
    if (-not $item.PSIsContainer) {
        return [pscustomobject]@{
            Files = 1L
            Bytes = [long]$item.Length
            Directories = 0L
        }
    }

    $fileCount = 0L
    $byteCount = 0L
    $directoryCount = 0L
    $stack = [Collections.Generic.Stack[string]]::new()
    $stack.Push($item.FullName)

    while ($stack.Count -gt 0) {
        $current = $stack.Pop()
        foreach ($child in Get-ChildItem -LiteralPath $current -Force `
            -ErrorAction SilentlyContinue) {
            if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                continue
            }
            if ($child.PSIsContainer) {
                $directoryCount++
                $stack.Push($child.FullName)
            }
            else {
                $fileCount++
                $byteCount += [long]$child.Length
            }
        }
    }

    return [pscustomobject]@{
        Files = $fileCount
        Bytes = $byteCount
        Directories = $directoryCount
    }
}

function Get-UniquePath {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $Path
    }

    $parent = Split-Path $Path -Parent
    $name = Split-Path $Path -Leaf
    $base = [IO.Path]::GetFileNameWithoutExtension($name)
    $extension = [IO.Path]::GetExtension($name)

    for ($index = 1; $index -lt 10000; $index++) {
        $candidate = Join-Path $parent (
            "{0}__{1}{2}" -f $base, $index, $extension
        )
        if (-not (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }
    throw "Benzersiz hedef adı üretilemedi: $Path"
}

function Remove-EmptyParents {
    param(
        [Parameter(Mandatory)][string]$Start,
        [Parameter(Mandatory)][string]$StopBefore
    )

    $current = $Start
    $stop = [IO.Path]::GetFullPath($StopBefore).TrimEnd("\")
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        $full = [IO.Path]::GetFullPath($current).TrimEnd("\")
        if ($full.Equals($stop, [StringComparison]::OrdinalIgnoreCase)) {
            break
        }
        if (-not (Test-Path -LiteralPath $full -PathType Container)) {
            $current = Split-Path $full -Parent
            continue
        }
        $item = Get-Item -LiteralPath $full -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            break
        }
        if (@(Get-ChildItem -LiteralPath $full -Force `
            -ErrorAction SilentlyContinue).Count -gt 0) {
            break
        }
        Remove-Item -LiteralPath $full -Force
        Add-Journal -Action "DeleteEmptyDirectory" -Source $full `
            -Status "Deleted"
        $current = Split-Path $full -Parent
    }
}

function Send-PathToRecycleBin {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Reason = "Gereksiz veya yeniden üretilebilir içerik"
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    Assert-InScope -Path $Path
    $stats = Get-TreeStats -Path $Path

    if ($Mode -eq "Preview") {
        Add-Journal -Action "Recycle" -Source $Path -Files $stats.Files `
            -Bytes $stats.Bytes -Status "Planned" -Note $Reason
        return
    }

    Add-Type -AssemblyName Microsoft.VisualBasic
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer) {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
            $item.FullName,
            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
        )
    }
    else {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
            $item.FullName,
            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
        )
    }
    Add-Journal -Action "Recycle" -Source $Path -Files $stats.Files `
        -Bytes $stats.Bytes -Status "Recycled" -Note $Reason
}

function Move-FileVerified {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        return
    }
    Assert-InScope -Path $Source
    Assert-InScope -Path $Destination
    $sourceItem = Get-Item -LiteralPath $Source -Force
    $sourceLength = [long]$sourceItem.Length
    $sourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
    $finalDestination = $Destination

    if (Test-Path -LiteralPath $Destination) {
        $destinationItem = Get-Item -LiteralPath $Destination -Force
        if (-not $destinationItem.PSIsContainer -and
            $destinationItem.Length -eq $sourceLength) {
            $destinationHash = (
                Get-FileHash -LiteralPath $Destination -Algorithm SHA256
            ).Hash
            if ($destinationHash -eq $sourceHash) {
                if ($Mode -eq "Preview") {
                    Add-Journal -Action "DeleteHashDuplicate" -Source $Source `
                        -Destination $Destination -Files 1 `
                        -Bytes $sourceLength -Status "Planned"
                }
                else {
                    Remove-Item -LiteralPath $Source -Force
                    Add-Journal -Action "DeleteHashDuplicate" -Source $Source `
                        -Destination $Destination -Files 1 `
                        -Bytes $sourceLength -Status "Deleted"
                }
                return
            }
        }
        $finalDestination = Get-UniquePath -Path $Destination
    }

    if ($Mode -eq "Preview") {
        Add-Journal -Action "MoveFile" -Source $Source `
            -Destination $finalDestination -Files 1 -Bytes $sourceLength `
            -Status "Planned"
        return
    }

    New-Item -ItemType Directory -Path (
        Split-Path $finalDestination -Parent
    ) -Force | Out-Null
    Move-Item -LiteralPath $Source -Destination $finalDestination
    $moved = Get-Item -LiteralPath $finalDestination -Force
    $movedHash = (
        Get-FileHash -LiteralPath $finalDestination -Algorithm SHA256
    ).Hash
    if ($moved.Length -ne $sourceLength -or
        $movedHash -ne $sourceHash) {
        throw "Taşıma doğrulaması başarısız: $Source"
    }
    Add-Journal -Action "MoveFile" -Source $Source `
        -Destination $finalDestination -Files 1 -Bytes $moved.Length `
        -Status "Moved"
}

function Move-DirectoryVerified {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        return
    }
    Assert-InScope -Path $Source
    Assert-InScope -Path $Destination
    $stats = Get-TreeStats -Path $Source
    $finalDestination = $Destination
    if (Test-Path -LiteralPath $Destination) {
        $finalDestination = Get-UniquePath -Path $Destination
    }

    if ($Mode -eq "Preview") {
        Add-Journal -Action "MoveDirectory" -Source $Source `
            -Destination $finalDestination -Files $stats.Files `
            -Bytes $stats.Bytes -Status "Planned"
        return
    }

    New-Item -ItemType Directory -Path (
        Split-Path $finalDestination -Parent
    ) -Force | Out-Null
    Move-Item -LiteralPath $Source -Destination $finalDestination
    $after = Get-TreeStats -Path $finalDestination
    if ($after.Files -ne $stats.Files -or $after.Bytes -ne $stats.Bytes) {
        throw "Klasör taşıma doğrulaması başarısız: $Source"
    }
    Add-Journal -Action "MoveDirectory" -Source $Source `
        -Destination $finalDestination -Files $stats.Files `
        -Bytes $stats.Bytes -Status "Moved"
}

function Merge-DirectoryContents {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        return
    }
    Assert-InScope -Path $Source
    Assert-InScope -Path $Destination

    $sourceRoot = [IO.Path]::GetFullPath($Source).TrimEnd("\")
    $files = @(
        Get-ChildItem -LiteralPath $sourceRoot -File -Recurse -Force `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $_.FullName -notmatch '(?i)[\\/]\.git([\\/]|$)'
            }
    )

    foreach ($file in $files) {
        $relative = $file.FullName.Substring($sourceRoot.Length).TrimStart("\")
        Move-FileVerified -Source $file.FullName `
            -Destination (Join-Path $Destination $relative)
    }

    if ($Mode -eq "Apply") {
        foreach ($directory in @(
            Get-ChildItem -LiteralPath $sourceRoot -Directory -Recurse -Force `
                -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.FullName -notmatch '(?i)[\\/]\.git([\\/]|$)' -and
                    -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)
                } |
                Sort-Object { $_.FullName.Length } -Descending
        )) {
            if (@(Get-ChildItem -LiteralPath $directory.FullName -Force `
                -ErrorAction SilentlyContinue).Count -eq 0) {
                Remove-Item -LiteralPath $directory.FullName -Force
            }
        }
        if ((Test-Path -LiteralPath $sourceRoot) -and
            @(Get-ChildItem -LiteralPath $sourceRoot -Force `
                -ErrorAction SilentlyContinue).Count -eq 0) {
            Remove-Item -LiteralPath $sourceRoot -Force
        }
    }
}

function Move-UniqueExecutable {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        return
    }
    $destinationDirectory = Join-Path $FileArchive (
        "EXE_Uygulamalar\UzantiDuzenleyici"
    )
    $sourceItem = Get-Item -LiteralPath $Source -Force
    $sourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash

    if (Test-Path -LiteralPath $destinationDirectory) {
        foreach ($existing in Get-ChildItem -LiteralPath $destinationDirectory `
            -File -Force -ErrorAction SilentlyContinue) {
            if ($existing.Length -ne $sourceItem.Length) {
                continue
            }
            $existingHash = (
                Get-FileHash -LiteralPath $existing.FullName -Algorithm SHA256
            ).Hash
            if ($existingHash -eq $sourceHash) {
                if ($Mode -eq "Preview") {
                    Add-Journal -Action "DeleteHashDuplicate" -Source $Source `
                        -Destination $existing.FullName -Files 1 `
                        -Bytes $sourceItem.Length -Status "Planned"
                }
                else {
                    Remove-Item -LiteralPath $Source -Force
                    Add-Journal -Action "DeleteHashDuplicate" -Source $Source `
                        -Destination $existing.FullName -Files 1 `
                        -Bytes $sourceItem.Length -Status "Deleted"
                }
                return
            }
        }
    }

    $cleanLabel = $Label -replace '[^\p{L}\p{Nd}._-]+', '_'
    $destination = Join-Path $destinationDirectory (
        "{0}__{1}" -f $cleanLabel, $sourceItem.Name
    )
    Move-FileVerified -Source $Source -Destination $destination
}

function Remove-GitHubJunctions {
    $junctionRoot = Join-Path $ProjectArchive "GitHub_Baglantilari"
    if (-not (Test-Path -LiteralPath $junctionRoot -PathType Container)) {
        return
    }

    foreach ($child in Get-ChildItem -LiteralPath $junctionRoot -Force `
        -ErrorAction SilentlyContinue) {
        if (-not ($child.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            continue
        }
        if ($Mode -eq "Preview") {
            Add-Journal -Action "DeleteRedundantJunction" `
                -Source $child.FullName -Status "Planned"
        }
        else {
            # Windows PowerShell 5, Remove-Item ile junction silerken bazen
            # NullReferenceException üretir. Directory.Delete bağlantının
            # kendisini kaldırır; hedef Git deposuna girmez.
            [IO.Directory]::Delete($child.FullName, $false)
            Add-Journal -Action "DeleteRedundantJunction" `
                -Source $child.FullName -Status "Deleted"
        }
    }
    if ($Mode -eq "Apply" -and
        @(Get-ChildItem -LiteralPath $junctionRoot -Force `
            -ErrorAction SilentlyContinue).Count -eq 0) {
        Remove-Item -LiteralPath $junctionRoot -Force
    }
}

function Remove-ReproducibleBuildWaste {
    $roots = @($ProjectArchive, $GitHubRoot, $DesktopApp)
    $names = @(
        "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache",
        ".ipynb_checkpoints", ".venv", "venv", "node_modules",
        "bin", "obj"
    )

    $candidates = [Collections.Generic.List[object]]::new()
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) {
            continue
        }
        foreach ($directory in Get-ChildItem -LiteralPath $root -Directory `
            -Recurse -Force -ErrorAction SilentlyContinue) {
            if ($directory.Name -notin $names) {
                continue
            }
            if ($directory.FullName -match '(?i)[\\/]\.git([\\/]|$)' -or
                $directory.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                continue
            }
            $candidates.Add($directory)
        }
    }

    $topOnly = @(
        $candidates |
            Sort-Object { $_.FullName.Length } |
            Where-Object {
                $candidate = $_.FullName
                -not ($candidates | Where-Object {
                    $_.FullName -ne $candidate -and
                    $candidate.StartsWith(
                        ($_.FullName.TrimEnd("\") + "\"),
                        [StringComparison]::OrdinalIgnoreCase
                    )
                })
            }
    )
    foreach ($directory in $topOnly) {
        Send-PathToRecycleBin -Path $directory.FullName `
            -Reason "Yeniden üretilebilir derleme/önbellek/sanal ortam"
    }
}

function Move-LegacyScientificFiles {
    $unclassified = Join-Path $ProjectArchive (
        "Bilimsel_Proje_Kodlari\00_INCELEME_GEREKTIREN_KODLAR"
    )
    if (-not (Test-Path -LiteralPath $unclassified -PathType Container)) {
        return
    }

    $legacyRepo = Join-Path $GitHubRoot "legacy-scientific-scripts"
    $pythonFolder = Join-Path $unclassified (
        "Local_C\Users\aoa02\Documents\PY"
    )
    $strongName = (
        "(?i)(lpg|obd|atiker|lit1002|cleanroom|litho|photomask|" +
        "mems|chemical|lcst|unam|mass[_-]?spect|powershell|codex|" +
        "github|bulut|flat_zip|recursive_flatten|smart_(rebundle|" +
        "universal)|universal_file_sorter|folder_cleanup|odtu|" +
        "portfolio|(^|_)cv(_|\.)|csv_to|missing_data|bos_veri|" +
        "veri_|sutun|satir|inventory|traceability|laboratory|" +
        "validation|calibration|fuel_|surus_|consumption_|pressure_|" +
        "vehicle_|compatibility_checker|dataset_|import_engine|" +
        "source_page_browser|adjustment_engine|analysis_engine|" +
        "reference_library|project_manager|data_editor|data_import|" +
        "column_mapping|provenance|gui_)"
    )
    $vendorName = (
        "^(?i)(_.*|hook-|cloudpickle|test_cloudpickle|" +
        "test_jupyterlab|jupyter\.py$|pylab_|excel_io)"
    )

    if (Test-Path -LiteralPath $pythonFolder) {
        foreach ($file in @(
            Get-ChildItem -LiteralPath $pythonFolder -File -Filter "*.py" `
                -Force -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.LastWriteTime -ge [datetime]"2026-07-01" -or
                    ($_.Name -match $strongName -and
                        $_.Name -notmatch $vendorName)
                }
        )) {
            Move-FileVerified -Source $file.FullName -Destination (
                Join-Path $legacyRepo ("python\" + $file.Name)
            )
        }
    }

    $notebookFolder = Join-Path $unclassified (
        "Local_C\Users\aoa02\Documents\IPYNB"
    )
    if (Test-Path -LiteralPath $notebookFolder) {
        foreach ($file in Get-ChildItem -LiteralPath $notebookFolder -File `
            -Force -ErrorAction SilentlyContinue) {
            Move-FileVerified -Source $file.FullName -Destination (
                Join-Path $legacyRepo ("notebooks\" + $file.Name)
            )
        }
    }

    $recentExtensions = @(
        ".ps1", ".psm1", ".bat", ".cmd", ".pyw", ".cs",
        ".html", ".txt", ".md", ".json", ".toml", ".yml", ".yaml"
    )
    foreach ($file in @(
        Get-ChildItem -LiteralPath $unclassified -File -Recurse -Force `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $_.LastWriteTime -ge [datetime]"2026-07-01" -and
                $_.Extension.ToLowerInvariant() -in $recentExtensions -and
                $_.Length -lt 2MB -and
                $_.FullName -notmatch (
                    "(?i)[\\/](Drivers|DriverBackup|AMD)([\\/]|$)"
                )
            }
    )) {
        $typeName = $file.Extension.TrimStart(".").ToUpperInvariant()
        if ([string]::IsNullOrWhiteSpace($typeName)) {
            $typeName = "DIGER"
        }
        Move-FileVerified -Source $file.FullName -Destination (
            Join-Path $legacyRepo (
                "misc_sources\{0}\{1}" -f $typeName, $file.Name
            )
        )
    }

    Send-PathToRecycleBin -Path $unclassified -Reason (
        "Proje yapısını kaybetmiş eski bağımlılık parçaları ve yedek toplama ağacı"
    )
}

function Move-ProjectCategories {
    $scientificRoot = Join-Path $ProjectArchive "Bilimsel_Proje_Kodlari"
    $mappings = @(
        @{
            Source = "01_Photomask_Design_and_Lithography_Tools"
            Repository = "mems-photomask-designer"
        },
        @{
            Source = "02_Cleanroom_Process_Planner"
            Repository = "cleanroom-process-planner"
        },
        @{
            Source = "06_General_Data_Tool"
            Repository = "general-data-tool"
        },
        @{
            Source = "07_Chemical_Storage_Planner"
            Repository = "chemical_storage_planner"
        },
        @{
            Source = "10_PowerShell_and_General_EXE_Builder"
            Repository = "powershell-general-exe-builder"
        }
    )

    foreach ($mapping in $mappings) {
        $source = Join-Path $scientificRoot $mapping.Source
        $destination = Join-Path (
            Join-Path $GitHubRoot $mapping.Repository
        ) ("legacy_imports\bilimsel_arsiv_20260726\" + $mapping.Source)
        Move-DirectoryVerified -Source $source -Destination $destination
    }
}

function Invoke-Organization {
    if ($Mode -eq "Apply") {
        New-Item -ItemType Directory -Path $GitHubRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $FileArchive -Force | Out-Null
        New-Item -ItemType Directory -Path $CentralLogRoot -Force | Out-Null
    }

    Remove-GitHubJunctions
    Remove-ReproducibleBuildWaste

    # Büyük bulut envanteri projesi koduyla birlikte taşınır. Üretilen raporlar
    # ve geçici çalışma alanı tekrar üretilebilir olduğu için çöpe gider.
    $cloudRepo = Join-Path $ProjectArchive "Bulut_Proje\Surumler\bulut_proje"
    Send-PathToRecycleBin -Path (Join-Path $cloudRepo "reports") `
        -Reason "Veritabanından yeniden üretilebilir raporlar"
    Send-PathToRecycleBin -Path (Join-Path $cloudRepo "work") `
        -Reason "Geçici çalışma çıktıları"
    Move-DirectoryVerified -Source $cloudRepo `
        -Destination (Join-Path $GitHubRoot "bulut-proje")

    # Yalnız .git içeren boş proje kabukları gerçek proje değildir.
    Send-PathToRecycleBin -Path (Join-Path $ProjectArchive "CV_Maker") `
        -Reason "Kaynak dosyası içermeyen boş Git proje kabuğu"
    Send-PathToRecycleBin -Path (Join-Path $ProjectArchive "ODTU_MEMS") `
        -Reason "Kaynak dosyası içermeyen boş Git proje kabuğu"

    # C# GUI projesinin farklı kaynak sürümleri korunur; bin/obj daha önce
    # temizlenir. Tekil yayın EXE'leri dosya kökenli arşive alınır.
    $guiRoot = Join-Path $ProjectArchive "Dosya_Duzenleyici_GUI"
    $guiExeOrder = @(
        @{
            Version = "v1.1"
            Path = "Surumler\UzantiDuzenleyici_Masaustu_v1_1"
        },
        @{
            Version = "v1.0.4"
            Path = "Surumler\UzantiDuzenleyici_v1_0_4_TAM_PAKET"
        },
        @{
            Version = "v1.0.2"
            Path = "Surumler\UzantiDuzenleyici_Masaustu_v1_0_2"
        }
    )
    foreach ($version in $guiExeOrder) {
        $versionRoot = Join-Path $guiRoot $version.Path
        foreach ($exe in @(
            Get-ChildItem -LiteralPath $versionRoot -File -Filter "*.exe" `
                -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.FullName -notmatch '(?i)[\\/](bin|obj)([\\/]|$)'
                }
        )) {
            $kind = if ($exe.FullName -match '(?i)[\\/]Kurulum[\\/]') {
                "Kurulum"
            }
            else {
                "Portable"
            }
            Move-UniqueExecutable -Source $exe.FullName -Label (
                "{0}_{1}" -f $version.Version, $kind
            )
        }
    }

    $guiVersions = @(
        @{
            Source = "Surumler\UzantiDuzenleyici_Masaustu_v1_0_2"
            Target = "versions\v1.0.2"
        },
        @{
            Source = "Surumler\UzantiDuzenleyici_v1_0_4_TAM_PAKET"
            Target = "versions\v1.0.4"
        },
        @{
            Source = "Surumler\UzantiDuzenleyici_Masaustu_v1_1"
            Target = "versions\v1.1"
        }
    )
    foreach ($version in $guiVersions) {
        Move-DirectoryVerified -Source (Join-Path $guiRoot $version.Source) `
            -Destination (
                Join-Path (Join-Path $GitHubRoot "uzanti-duzenleyici") `
                    $version.Target
            )
    }
    Move-DirectoryVerified -Source (
        Join-Path $guiRoot (
            "Surumler\UzantiDuzenleyici_Masaustu_v1_0_3_TAM_PAKET"
        )
    ) -Destination (
        Join-Path $GitHubRoot "uzanti-duzenleyici\versions\v1.0.3"
    )
    Move-DirectoryVerified -Source (
        Join-Path $guiRoot (
            "Surumler\Masaustu_Duzenleyici_Uygulamasi_v2_20260726"
        )
    ) -Destination (
        Join-Path $GitHubRoot (
            "deskopt_sorter\legacy_versions\v2_20260726"
        )
    )
    foreach ($legacyGui in @(
        "UzantiDuzenleyici_Masaustu_v1",
        "UzantiDuzenleyici_v1_0_3_ESKI_KLASOR_TAM_ONARIM",
        "Uzanti_Duzenleyici_GUI_PAKET"
    )) {
        Move-DirectoryVerified -Source (
            Join-Path $guiRoot ("Surumler\" + $legacyGui)
        ) -Destination (
            Join-Path $GitHubRoot (
                "uzanti-duzenleyici\legacy_sources\" + $legacyGui
            )
        )
    }
    Merge-DirectoryContents -Source (
        Join-Path $guiRoot "Bagimsiz_Dosyalar"
    ) -Destination (
        Join-Path $GitHubRoot "uzanti-duzenleyici\legacy_sources"
    )
    Merge-DirectoryContents -Source (
        Join-Path $guiRoot "Indirilen_Surumler"
    ) -Destination (
        Join-Path $GitHubRoot "uzanti-duzenleyici\downloaded_versions"
    )

    # Masaüstü uygulamasının çalışan kaynakları boş çevrim içi depoya taşınır.
    Merge-DirectoryContents -Source $DesktopApp -Destination (
        Join-Path $GitHubRoot "deskopt_sorter"
    )

    # İşlem günlükleri tek merkezi klasörde toplanır.
    $oldLog = Join-Path $DesktopOrganized "_ISLEM_KAYITLARI"
    Merge-DirectoryContents -Source $oldLog -Destination (
        Join-Path $CentralLogRoot "Masaustu_Duzenleyici"
    )

    # Masaüstünden toplanan gerçek kaynaklar ilgili mevcut depolara katılır.
    $desktopProjects = Join-Path $ProjectArchive "Masaustu_Kaynak_Projeleri"
    $cleanroomBase = Join-Path $desktopProjects (
        "02_Cleanroom_Process_Planner\00_Proje_ve_Kaynak_Klasorleri"
    )
    Move-DirectoryVerified -Source (
        Join-Path $cleanroomBase (
            "Codex_Full_Cleanroom_Automation_v1.5.1_SRC_IMPORT_FIX"
        )
    ) -Destination (
        Join-Path $GitHubRoot (
            "cleanroom-process-planner\tools\" +
            "cleanroom-portfolio-automation-v1.5.1"
        )
    )
    Send-PathToRecycleBin -Path (
        Join-Path $cleanroomBase (
            "Codex_Full_Cleanroom_Automation_v1.3_NATIVE_STDERR_FIXED_READY"
        )
    ) -Reason "Daha eski otomasyon sürümü; v1.5.1 kaynak sürümü korundu"
    Send-PathToRecycleBin -Path (
        Join-Path $cleanroomBase (
            "Codex_Full_Cleanroom_Automation_v1.5_HOST_ONLY_FINALIZER"
        )
    ) -Reason "Daha eski otomasyon sürümü; v1.5.1 kaynak sürümü korundu"
    Send-PathToRecycleBin -Path (
        Join-Path $desktopProjects "02_Cleanroom_Process_Planner\03_Arsivler"
    ) -Reason "ZIP sürüm yedekleri; kaynak sürüm korundu"

    Merge-DirectoryContents -Source (
        Join-Path $desktopProjects "10_PowerShell_and_General_EXE_Builder"
    ) -Destination (
        Join-Path $GitHubRoot (
            "powershell-general-exe-builder\legacy_imports\" +
            "masaustu-powershell-araclari"
        )
    )
    Send-PathToRecycleBin -Path (
        Join-Path $GitHubRoot (
            "powershell-general-exe-builder\legacy_imports\" +
            "masaustu-powershell-araclari\02_Uygulamalar\EXE\test_cikti.exe"
        )
    ) -Reason "Yalnız test amacıyla üretilmiş EXE çıktısı"
    Merge-DirectoryContents -Source (
        Join-Path $desktopProjects "11_Eposta_ve_Thunderbird"
    ) -Destination (
        Join-Path $GitHubRoot (
            "powershell-general-exe-builder\windows_tools\bilkent-thunderbird"
        )
    )
    Merge-DirectoryContents -Source (
        Join-Path $desktopProjects "12_Windows_ve_Ag_Araclari"
    ) -Destination (
        Join-Path $GitHubRoot (
            "powershell-general-exe-builder\windows_tools\windows-network"
        )
    )

    # Kaynak ZIP yedekleri artık istenmediği için önce topluca çöpe gider.
    $scientificRoot = Join-Path $ProjectArchive "Bilimsel_Proje_Kodlari"
    if (Test-Path -LiteralPath $scientificRoot) {
        foreach ($archive in @(
            Get-ChildItem -LiteralPath $scientificRoot -File -Recurse -Force `
                -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Extension.ToLowerInvariant() -in @(
                        ".zip", ".7z", ".rar"
                    )
                }
        )) {
            Send-PathToRecycleBin -Path $archive.FullName `
                -Reason "İstenmeyen sıkıştırılmış yedek"
        }
    }

    Send-PathToRecycleBin -Path (Join-Path $scientificRoot "_REPORTS") `
        -Reason "Eski toplama işleminin yeniden üretilebilir manifestleri"
    Move-LegacyScientificFiles
    Move-ProjectCategories
    Send-PathToRecycleBin -Path (
        Join-Path $scientificRoot "05_UNAM_Mass_Spectrometry_Pipeline"
    ) -Reason "Yalnız sıfır baytlık yer tutucu içeriyor"

    # Tanınmayan BAU uzantısı proje değildir; bağımsız dosya olarak saklanır.
    $bauRoot = Join-Path $ProjectArchive "BAU"
    if (Test-Path -LiteralPath $bauRoot) {
        foreach ($bauFile in Get-ChildItem -LiteralPath $bauRoot -File `
            -Recurse -Force -ErrorAction SilentlyContinue) {
            Move-FileVerified -Source $bauFile.FullName -Destination (
                Join-Path $FileArchive ("Diger_Dosyalar\BAU\" + $bauFile.Name)
            )
        }
    }

    # Kalan boş/işlevsiz üst kabuklar temizlenir. Beklenmeyen gerçek dosya
    # kalırsa PROJE_ARSIVI kökü otomatik çöpe gönderilmez.
    if ($Mode -eq "Apply") {
        foreach ($root in @($desktopProjects, $DesktopOrganized, $ProjectArchive)) {
            if (-not (Test-Path -LiteralPath $root -PathType Container)) {
                continue
            }
            foreach ($directory in @(
                Get-ChildItem -LiteralPath $root -Directory -Recurse -Force `
                    -ErrorAction SilentlyContinue |
                    Where-Object {
                        -not ($_.Attributes -band
                            [IO.FileAttributes]::ReparsePoint)
                    } |
                    Sort-Object { $_.FullName.Length } -Descending
            )) {
                if (@(Get-ChildItem -LiteralPath $directory.FullName -Force `
                    -ErrorAction SilentlyContinue).Count -eq 0) {
                    Remove-Item -LiteralPath $directory.FullName -Force
                    Add-Journal -Action "DeleteEmptyDirectory" `
                        -Source $directory.FullName -Status "Deleted"
                }
            }
        }
        foreach ($root in @($DesktopOrganized, $ProjectArchive)) {
            if ((Test-Path -LiteralPath $root -PathType Container) -and
                @(Get-ChildItem -LiteralPath $root -Force `
                    -ErrorAction SilentlyContinue).Count -eq 0) {
                Remove-Item -LiteralPath $root -Force
                Add-Journal -Action "DeleteEmptyDirectory" -Source $root `
                    -Status "Deleted"
            }
        }
    }

    $runId = Get-Date -Format "yyyyMMdd_HHmmss"
    if ($Mode -eq "Preview") {
        $plannedFiles = 0L
        $plannedBytes = 0L
        if ($script:Journal.Count -gt 0) {
            $plannedFiles = [long]((
                $script:Journal | Measure-Object Files -Sum
            ).Sum)
            $plannedBytes = [long]((
                $script:Journal | Measure-Object Bytes -Sum
            ).Sum)
        }
        return [pscustomobject]@{
            Mode = "Preview"
            PlannedActions = $script:Journal.Count
            PlannedFiles = $plannedFiles
            PlannedBytes = $plannedBytes
        }
    }

    $logPath = Join-Path $CentralLogRoot (
        "sade_duzenleme_{0}.csv" -f $runId
    )
    $summaryPath = Join-Path $CentralLogRoot (
        "sade_duzenleme_ozet_{0}.json" -f $runId
    )
    $script:Journal.ToArray() |
        Export-Csv -LiteralPath $logPath -NoTypeInformation -Encoding UTF8

    $summary = [ordered]@{
        Mode = "Apply"
        RunId = $runId
        Moved = @($script:Journal | Where-Object {
            $_.Status -eq "Moved"
        }).Count
        Recycled = @($script:Journal | Where-Object {
            $_.Status -eq "Recycled"
        }).Count
        DuplicateFilesDeleted = @($script:Journal | Where-Object {
            $_.Action -eq "DeleteHashDuplicate" -and
            $_.Status -eq "Deleted"
        }).Count
        Errors = @($script:Journal | Where-Object {
            $_.Status -eq "Error"
        }).Count
        LogPath = $logPath
        FinishedAt = (Get-Date).ToString("o")
    }
    $summary | ConvertTo-Json |
        Set-Content -LiteralPath $summaryPath -Encoding UTF8
    return [pscustomobject]$summary
}

try {
    $result = Invoke-Organization
    if ($Mode -eq "Preview") {
        $script:Journal.ToArray() |
            Sort-Object Bytes -Descending |
            Format-Table Action, Files, Bytes, Source, Destination -Wrap
    }
    $result | Format-List
}
catch {
    Write-Error (
        "Düzenleme durduruldu. Neden: {0}" -f $_.Exception.Message
    )
    exit 1
}
