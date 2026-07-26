[CmdletBinding()]
param(
    [ValidateSet("Gui", "Preview", "Move", "UndoLast")]
    [string]$Mode = "Gui",

    [string]$SourceRoot = [Environment]::GetFolderPath("Desktop"),

    [string]$DestinationRoot = (
        [Environment]::GetFolderPath("MyDocuments")
    ),

    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Bu uygulama yalnız masaüstünün doğrudan içindeki öğeleri işler.
# Proje klasörlerinin içini parçalamaz; klasörü tek parça halinde taşır.
# Böylece çalışan bir projenin klasör yapısı korunur.

$script:ProtectedDesktopNames = @(
    "desktop.ini",
    "Masaustunu_Duzenle.lnk",
    "Masaustunu_Duzenle.cmd",
    "Dosyalarimi_Duzenle.lnk"
)

$script:ProjectRules = @(
    [pscustomobject]@{
        Folder = "00_Birlesik_Proje_Kod_Arsivi"
        Keywords = @(
            "bilimsel_proje_kod_arsivi",
            "bilimsel proje kod arsivi"
        )
    },
    [pscustomobject]@{
        Folder = "01_Photomask_Design_and_Lithography_Tools"
        Keywords = @(
            "photomask", "photo mask", "fotomaske", "mask design",
            "mask maker", "lithography", "litografi", "gdsii", "klayout"
        )
    },
    [pscustomobject]@{
        Folder = "02_Cleanroom_Process_Planner"
        Keywords = @(
            "cleanroom", "clean room", "temiz oda", "process planner",
            "proses planlayici", "wafer process"
        )
    },
    [pscustomobject]@{
        Folder = "03_Laboratory_Safety_Poster_and_SOP_Editor"
        Keywords = @(
            "laboratory safety", "lab safety", "laboratuvar guvenligi",
            "safety poster", "sop editor", "standard operating procedure"
        )
    },
    [pscustomobject]@{
        Folder = "04_Laboratory_Inventory_and_Traceability_System"
        Keywords = @(
            "laboratory inventory", "lab inventory", "envanter",
            "traceability", "sample tracking", "numune takip",
            "stock tracking", "stok takip"
        )
    },
    [pscustomobject]@{
        Folder = "05_UNAM_Mass_Spectrometry_Pipeline"
        Keywords = @(
            "unam", "mass spectrometry", "mass spec", "kutle spektrometri",
            "lcms", "gcms", "maldi", "qtof", "mzml", "mzxml"
        )
    },
    [pscustomobject]@{
        Folder = "06_General_Data_Tool"
        Keywords = @(
            "general data", "genel veri", "data tool", "csv converter",
            "csv to excel", "file data control", "veri donusturucu"
        )
    },
    [pscustomobject]@{
        Folder = "07_Chemical_Storage_Planner"
        Keywords = @(
            "chemical storage", "kimyasal depolama", "kimyasal depo",
            "chemical compatibility", "kimyasal uyumluluk",
            "segregation matrix"
        )
    },
    [pscustomobject]@{
        Folder = "08_Validation_Toolkit"
        Keywords = @(
            "validation toolkit", "validation tool", "validasyon",
            "method validation", "verification toolkit", "qa toolkit"
        )
    },
    [pscustomobject]@{
        Folder = "09_LCST_and_Scientific_Data_Analysis_Tools"
        Keywords = @(
            "lcst", "lower critical solution temperature", "cloud point",
            "scientific data analysis", "bilimsel veri analizi",
            "calibration curve", "lod loq", "rsd", "sensor data"
        )
    },
    [pscustomobject]@{
        Folder = "11_Eposta_ve_Thunderbird"
        Keywords = @(
            "thunderbird", "bilkent mail", "bilkent eposta",
            "e-posta", "eposta", "email", "mailbox"
        )
    },
    [pscustomobject]@{
        Folder = "12_Windows_ve_Ag_Araclari"
        Keywords = @(
            "windows ag", "network reset", "ag sifirlama",
            "restart tani", "windows onar", "sistem tani"
        )
    },
    [pscustomobject]@{
        Folder = "13_Dosya_Duzenleme_ve_Yedekleme"
        Keywords = @(
            "duzenleyici", "düzenleyici", "extension sorter", "sorter",
            "ana_klasore", "ana klasore", "turune gore", "türüne göre",
            "yedek", "backup", "downloads", "dosya arsivi"
        )
    },
    [pscustomobject]@{
        Folder = "10_PowerShell_and_General_EXE_Builder"
        Keywords = @(
            "powershell", "power shell", "exe builder", "pyinstaller",
            "python exe", "build exe", "codex status", "ps2exe"
        )
    }
)

function Get-NormalizedPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $full = [System.IO.Path]::GetFullPath(
        [Environment]::ExpandEnvironmentVariables($Path)
    )

    if ($full.Length -gt 3) {
        return $full.TrimEnd("\")
    }

    return $full
}

function Test-PathInside {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ChildPath,

        [Parameter(Mandatory = $true)]
        [string]$ParentPath
    )

    $child = Get-NormalizedPath -Path $ChildPath
    $parent = Get-NormalizedPath -Path $ParentPath

    if ($child.Equals($parent, [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    $prefix = $parent.TrimEnd("\") + "\"
    return $child.StartsWith(
        $prefix,
        [StringComparison]::OrdinalIgnoreCase
    )
}

function ConvertTo-SearchText {
    param(
        [AllowEmptyString()]
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    $normalized = $Text.Normalize(
        [Text.NormalizationForm]::FormD
    )
    $builder = New-Object Text.StringBuilder

    foreach ($character in $normalized.ToCharArray()) {
        $category = [Globalization.CharUnicodeInfo]::GetUnicodeCategory(
            $character
        )
        if ($category -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$builder.Append($character)
        }
    }

    $plain = $builder.ToString().Normalize(
        [Text.NormalizationForm]::FormC
    ).ToLowerInvariant()

    $plain = $plain -replace "[_\-.]+", " "
    $plain = $plain -replace "\s+", " "
    return $plain.Trim()
}

function Get-ProjectFolder {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileSystemInfo]$Item
    )

    $searchText = ConvertTo-SearchText -Text $Item.Name

    foreach ($rule in $script:ProjectRules) {
        foreach ($keyword in $rule.Keywords) {
            $normalizedKeyword = ConvertTo-SearchText -Text $keyword
            if (
                -not [string]::IsNullOrWhiteSpace($normalizedKeyword) -and
                $searchText.Contains($normalizedKeyword)
            ) {
                return $rule.Folder
            }
        }
    }

    if (-not $Item.PSIsContainer) {
        $codeExtensions = @(
            ".ps1", ".psm1", ".psd1", ".bat", ".cmd", ".vbs",
            ".py", ".pyw", ".spec", ".exe", ".msi"
        )
        if ($codeExtensions -contains $Item.Extension.ToLowerInvariant()) {
            return "10_PowerShell_and_General_EXE_Builder"
        }
    }

    return "99_Genel_Masaustu_Dosyalari"
}

function Get-RepositoryName {
    param([Parameter(Mandatory = $true)][string]$ProjectFolder)

    $mapping = @{
        "01_Photomask_Design_and_Lithography_Tools" = "mems-photomask-designer"
        "02_Cleanroom_Process_Planner" = "cleanroom-process-planner"
        "03_Laboratory_Safety_Poster_and_SOP_Editor" = "laboratory-safety-sop-editor"
        "04_Laboratory_Inventory_and_Traceability_System" = "laboratory-inventory-traceability-system"
        "05_UNAM_Mass_Spectrometry_Pipeline" = "unam-mass-spectrometry-pipeline"
        "06_General_Data_Tool" = "general-data-tool"
        "07_Chemical_Storage_Planner" = "chemical_storage_planner"
        "08_Validation_Toolkit" = "validation-toolkit"
        "09_LCST_and_Scientific_Data_Analysis_Tools" = "lcst-scientific-data-analysis-tools"
        "10_PowerShell_and_General_EXE_Builder" = "powershell-general-exe-builder"
        "13_Dosya_Duzenleme_ve_Yedekleme" = "deskopt_sorter"
    }

    if ($mapping.ContainsKey($ProjectFolder)) {
        return $mapping[$ProjectFolder]
    }
    return "legacy-scientific-scripts"
}

function Test-LikelyProjectDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileSystemInfo]$Item
    )

    if (-not $Item.PSIsContainer) {
        return $false
    }

    $markers = @(
        ".git", "pyproject.toml", "requirements.txt", "setup.py",
        "package.json", "Cargo.toml", "go.mod", "pom.xml"
    )
    $codeExtensions = @(
        ".py", ".pyw", ".ipynb", ".ps1", ".psm1", ".bat", ".cmd",
        ".cs", ".csproj", ".sln", ".js", ".ts", ".html", ".css"
    )
    $codeCount = 0

    foreach ($child in Get-ChildItem -LiteralPath $Item.FullName -Force `
        -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 250) {
        if ($child.Name -in $markers) {
            return $true
        }
        if (-not $child.PSIsContainer -and
            $child.Extension.ToLowerInvariant() -in $codeExtensions) {
            $codeCount++
            if ($codeCount -ge 2) {
                return $true
            }
        }
    }
    return $false
}

function Get-TypeFolder {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileSystemInfo]$Item
    )

    if ($Item.PSIsContainer) {
        return "00_Proje_ve_Kaynak_Klasorleri"
    }

    $extension = $Item.Extension.ToLowerInvariant()
    $extensionFolder = if ([string]::IsNullOrWhiteSpace($extension)) {
        "UZANTISIZ"
    }
    else {
        $extension.TrimStart(".").ToUpperInvariant()
    }

    $group = switch ($extension) {
        { $_ -in @(
            ".ps1", ".psm1", ".psd1", ".ps1xml", ".bat", ".cmd",
            ".vbs", ".sh", ".py", ".pyw", ".ipynb", ".r", ".rmd",
            ".qmd", ".jl", ".m", ".c", ".h", ".cpp", ".hpp", ".cs",
            ".vb", ".java", ".js", ".jsx", ".ts", ".tsx", ".html",
            ".css", ".sql", ".spec", ".ui"
        ) } { "01_Kod_ve_Scriptler"; break }

        { $_ -in @(".exe", ".msi", ".msix", ".appx") } {
            "02_Uygulamalar"; break
        }

        { $_ -in @(".zip", ".7z", ".rar", ".tar", ".gz", ".bz2") } {
            "03_Arsivler"; break
        }

        { $_ -in @(
            ".txt", ".md", ".rtf", ".pdf", ".doc", ".docx",
            ".odt", ".tex", ".epub"
        ) } { "04_Belgeler"; break }

        { $_ -in @(
            ".csv", ".tsv", ".xls", ".xlsx", ".xlsm", ".ods",
            ".json", ".jsonl", ".ndjson", ".xml", ".yaml", ".yml",
            ".toml", ".db", ".sqlite", ".sqlite3"
        ) } { "05_Veri_ve_Tablolar"; break }

        { $_ -in @(
            ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".tif",
            ".tiff", ".svg", ".webp", ".ico"
        ) } { "06_Gorseller"; break }

        { $_ -in @(
            ".mp3", ".wav", ".flac", ".m4a", ".mp4", ".mkv",
            ".avi", ".mov", ".wmv", ".webm"
        ) } { "07_Ses_ve_Video"; break }

        { $_ -in @(".lnk", ".url") } { "08_Kisayollar"; break }

        default { "99_Diger" }
    }

    return Join-Path -Path $group -ChildPath $extensionFolder
}

function Get-UniqueDestination {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Directory,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [Collections.Generic.HashSet[string]]$Reserved
    )

    $candidate = Join-Path -Path $Directory -ChildPath $Name
    $baseName = [IO.Path]::GetFileNameWithoutExtension($Name)
    $extension = [IO.Path]::GetExtension($Name)
    $counter = 1

    while (
        (Test-Path -LiteralPath $candidate) -or
        $Reserved.Contains($candidate)
    ) {
        $newName = "{0}__Masaustu_{1}{2}" -f $baseName, $counter, $extension
        $candidate = Join-Path -Path $Directory -ChildPath $newName
        $counter++
    }

    [void]$Reserved.Add($candidate)
    return $candidate
}

function Get-DirectoryStatistics {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $fileCount = 0
    [long]$totalBytes = 0
    $readErrors = 0

    try {
        $files = Get-ChildItem -LiteralPath $Path -File -Recurse -Force `
            -ErrorAction SilentlyContinue -ErrorVariable readProblem

        foreach ($file in $files) {
            $fileCount++
            $totalBytes += [long]$file.Length
        }

        if ($readProblem) {
            $readErrors = @($readProblem).Count
        }
    }
    catch {
        $readErrors++
    }

    return [pscustomobject]@{
        FileCount = $fileCount
        TotalBytes = $totalBytes
        ReadErrors = $readErrors
    }
}

function Assert-SafeRoots {
    $script:SourceRoot = Get-NormalizedPath -Path $script:SourceRoot
    $script:DestinationRoot = Get-NormalizedPath -Path $script:DestinationRoot

    if (-not (Test-Path -LiteralPath $script:SourceRoot -PathType Container)) {
        throw "Kaynak masaüstü klasörü bulunamadı: $script:SourceRoot"
    }

    if (
        (Test-PathInside -ChildPath $script:DestinationRoot `
            -ParentPath $script:SourceRoot) -or
        (Test-PathInside -ChildPath $script:SourceRoot `
            -ParentPath $script:DestinationRoot)
    ) {
        throw "Kaynak ve hedef klasör birbirinin içinde olamaz."
    }
}

function Get-DesktopPlan {
    Assert-SafeRoots

    $reserved = New-Object `
        "Collections.Generic.HashSet[string]" `
        ([StringComparer]::OrdinalIgnoreCase)

    $items = Get-ChildItem -LiteralPath $script:SourceRoot -Force |
        Where-Object {
            $script:ProtectedDesktopNames -notcontains $_.Name
        } |
        Sort-Object @{ Expression = { -not $_.PSIsContainer } }, Name

    $plan = New-Object Collections.Generic.List[object]

    foreach ($item in $items) {
        $isReparsePoint = (
            $item.Attributes -band [IO.FileAttributes]::ReparsePoint
        ) -ne 0

        $project = Get-ProjectFolder -Item $item
        $typeFolder = Get-TypeFolder -Item $item
        $githubRoot = Join-Path $script:DestinationRoot "GitHub_Projeleri"
        $fileRoot = Join-Path $script:DestinationRoot (
            "DOSYA_KOKENLI_ARSIV\Masaustu_Gelenleri"
        )

        if ($item.PSIsContainer -and
            (Test-LikelyProjectDirectory -Item $item)) {
            $repository = Get-RepositoryName -ProjectFolder $project
            $destinationDirectory = Join-Path (
                Join-Path $githubRoot $repository
            ) "incoming_desktop_projects"
        }
        elseif ($item.PSIsContainer) {
            $destinationDirectory = Join-Path $fileRoot "Klasorler"
        }
        elseif ($typeFolder -like "01_Kod_ve_Scriptler*") {
            $repository = if ($item.Extension.ToLowerInvariant() -in @(
                ".py", ".pyw", ".ipynb"
            )) {
                "legacy-scientific-scripts"
            }
            else {
                Get-RepositoryName -ProjectFolder $project
            }
            $destinationDirectory = Join-Path (
                Join-Path $githubRoot $repository
            ) ("incoming_desktop_files\" + $typeFolder)
        }
        else {
            $destinationDirectory = Join-Path $fileRoot $typeFolder
        }

        $destination = Get-UniqueDestination `
            -Directory $destinationDirectory `
            -Name $item.Name `
            -Reserved $reserved

        $plan.Add([pscustomobject]@{
            Source = $item.FullName
            Destination = $destination
            Name = $item.Name
            ItemType = if ($item.PSIsContainer) { "Folder" } else { "File" }
            Project = $project
            TypeFolder = $typeFolder
            Extension = if ($item.PSIsContainer) {
                ""
            }
            else {
                $item.Extension.ToLowerInvariant()
            }
            SizeBytes = if ($item.PSIsContainer) {
                0
            }
            else {
                [long]$item.Length
            }
            IsReparsePoint = $isReparsePoint
        })
    }

    return $plan.ToArray()
}

function Write-RunFiles {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Records,

        [Parameter(Mandatory = $true)]
        [string]$RunId,

        [Parameter(Mandatory = $true)]
        [string]$Operation
    )

    $logRoot = Join-Path $script:DestinationRoot (
        "_BELGELER_DUZENLEME_KAYITLARI\Masaustu_Duzenleyici"
    )
    if (-not (Test-Path -LiteralPath $logRoot)) {
        New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    }

    $manifestPath = Join-Path `
        $logRoot `
        ("{0}_manifest_{1}.csv" -f $Operation.ToLowerInvariant(), $RunId)

    $summaryPath = Join-Path `
        $logRoot `
        ("{0}_summary_{1}.json" -f $Operation.ToLowerInvariant(), $RunId)

    $Records |
        Export-Csv -LiteralPath $manifestPath `
            -NoTypeInformation -Encoding UTF8

    $summary = [ordered]@{
        RunId = $RunId
        Operation = $Operation
        SourceRoot = $script:SourceRoot
        DestinationRoot = $script:DestinationRoot
        FinishedAt = (Get-Date).ToString("o")
        Total = @($Records).Count
        Moved = @($Records | Where-Object Status -eq "Moved").Count
        Restored = @($Records | Where-Object Status -eq "Restored").Count
        Skipped = @(
            $Records |
                Where-Object Status -in @(
                    "SkippedReparsePoint",
                    "SkippedMissing",
                    "SkippedSourceOccupied"
                )
        ).Count
        Errors = @($Records | Where-Object Status -eq "Error").Count
        ManifestPath = $manifestPath
    }

    $summary |
        ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath $summaryPath -Encoding UTF8

    return [pscustomobject]@{
        ManifestPath = $manifestPath
        SummaryPath = $summaryPath
        Summary = [pscustomobject]$summary
    }
}

function Invoke-DesktopMove {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Plan
    )

    $runId = Get-Date -Format "yyyyMMdd_HHmmss"
    $records = New-Object Collections.Generic.List[object]

    foreach ($entry in $Plan) {
        $status = ""
        $errorMessage = ""
        $hashBefore = ""
        $hashAfter = ""
        [long]$sizeBytes = [long]$entry.SizeBytes
        $fileCount = if ($entry.ItemType -eq "File") { 1 } else { 0 }
        $destination = [string]$entry.Destination

        try {
            if (-not (Test-Path -LiteralPath $entry.Source)) {
                $status = "SkippedMissing"
            }
            elseif ($entry.IsReparsePoint) {
                $status = "SkippedReparsePoint"
            }
            else {
                $destinationDirectory = Split-Path -Parent $destination
                if (-not (Test-Path -LiteralPath $destinationDirectory)) {
                    New-Item -ItemType Directory `
                        -Path $destinationDirectory -Force | Out-Null
                }

                if ($entry.ItemType -eq "File") {
                    $hashBefore = (
                        Get-FileHash -LiteralPath $entry.Source `
                            -Algorithm SHA256
                    ).Hash

                    Move-Item -LiteralPath $entry.Source `
                        -Destination $destination

                    $hashAfter = (
                        Get-FileHash -LiteralPath $destination `
                            -Algorithm SHA256
                    ).Hash

                    if ($hashBefore -ne $hashAfter) {
                        throw "Taşıma sonrası SHA-256 doğrulaması başarısız."
                    }
                }
                else {
                    $before = Get-DirectoryStatistics -Path $entry.Source
                    $sizeBytes = [long]$before.TotalBytes
                    $fileCount = [int]$before.FileCount

                    Move-Item -LiteralPath $entry.Source `
                        -Destination $destination

                    $after = Get-DirectoryStatistics -Path $destination
                    if (
                        $before.FileCount -ne $after.FileCount -or
                        $before.TotalBytes -ne $after.TotalBytes
                    ) {
                        throw (
                            "Klasör doğrulaması başarısız. " +
                            "Dosya sayısı veya toplam boyut değişti."
                        )
                    }
                }

                $status = "Moved"
            }
        }
        catch {
            $status = "Error"
            $errorMessage = $_.Exception.Message

            # Dosya hedefe geçmiş fakat hash kontrolü başarısız olmuşsa,
            # mümkün olduğunda eski yerine geri koymayı deneriz.
            if (
                -not (Test-Path -LiteralPath $entry.Source) -and
                (Test-Path -LiteralPath $destination) -and
                -not (Test-Path -LiteralPath $entry.Source)
            ) {
                try {
                    $sourceParent = Split-Path -Parent $entry.Source
                    if (-not (Test-Path -LiteralPath $sourceParent)) {
                        New-Item -ItemType Directory `
                            -Path $sourceParent -Force | Out-Null
                    }
                    Move-Item -LiteralPath $destination `
                        -Destination $entry.Source
                    $errorMessage += " Kaynak konuma geri alındı."
                }
                catch {
                    $errorMessage += (
                        " Otomatik geri alma da başarısız: " +
                        $_.Exception.Message
                    )
                }
            }
        }

        $records.Add([pscustomobject][ordered]@{
            RunId = $runId
            Timestamp = (Get-Date).ToString("o")
            Source = $entry.Source
            Destination = $destination
            ItemType = $entry.ItemType
            Project = $entry.Project
            TypeFolder = $entry.TypeFolder
            Extension = $entry.Extension
            Action = "Move"
            Status = $status
            SizeBytes = $sizeBytes
            FileCount = $fileCount
            HashBefore = $hashBefore
            HashAfter = $hashAfter
            Error = $errorMessage
        })
    }

    return Write-RunFiles `
        -Records $records.ToArray() `
        -RunId $runId `
        -Operation "Move"
}

function Get-LatestMoveManifest {
    $logRoot = Join-Path $script:DestinationRoot (
        "_BELGELER_DUZENLEME_KAYITLARI\Masaustu_Duzenleyici"
    )
    if (-not (Test-Path -LiteralPath $logRoot -PathType Container)) {
        return $null
    }

    return Get-ChildItem -LiteralPath $logRoot `
        -Filter "move_manifest_*.csv" -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Invoke-UndoLastMove {
    Assert-SafeRoots

    $latestManifest = Get-LatestMoveManifest
    if ($null -eq $latestManifest) {
        throw "Geri alınabilecek bir taşıma manifesti bulunamadı."
    }

    $runId = Get-Date -Format "yyyyMMdd_HHmmss"
    $moveRows = @(Import-Csv -LiteralPath $latestManifest.FullName)
    [array]::Reverse($moveRows)

    $records = New-Object Collections.Generic.List[object]

    foreach ($row in $moveRows) {
        if ($row.Status -ne "Moved") {
            continue
        }

        $status = ""
        $errorMessage = ""
        $hashAfter = ""

        try {
            if (-not (Test-Path -LiteralPath $row.Destination)) {
                $status = "SkippedMissing"
            }
            elseif (Test-Path -LiteralPath $row.Source) {
                $status = "SkippedSourceOccupied"
            }
            else {
                $sourceParent = Split-Path -Parent $row.Source
                if (-not (Test-Path -LiteralPath $sourceParent)) {
                    New-Item -ItemType Directory `
                        -Path $sourceParent -Force | Out-Null
                }

                Move-Item -LiteralPath $row.Destination `
                    -Destination $row.Source

                if ($row.ItemType -eq "File") {
                    $hashAfter = (
                        Get-FileHash -LiteralPath $row.Source `
                            -Algorithm SHA256
                    ).Hash

                    if (
                        -not [string]::IsNullOrWhiteSpace($row.HashBefore) -and
                        $hashAfter -ne $row.HashBefore
                    ) {
                        throw "Geri alma sonrası SHA-256 eşleşmedi."
                    }
                }

                $status = "Restored"
            }
        }
        catch {
            $status = "Error"
            $errorMessage = $_.Exception.Message
        }

        $records.Add([pscustomobject][ordered]@{
            RunId = $runId
            Timestamp = (Get-Date).ToString("o")
            Source = $row.Destination
            Destination = $row.Source
            ItemType = $row.ItemType
            Project = $row.Project
            TypeFolder = $row.TypeFolder
            Extension = $row.Extension
            Action = "Undo"
            Status = $status
            SizeBytes = $row.SizeBytes
            FileCount = $row.FileCount
            HashBefore = $row.HashBefore
            HashAfter = $hashAfter
            Error = $errorMessage
        })
    }

    return Write-RunFiles `
        -Records $records.ToArray() `
        -RunId $runId `
        -Operation "Undo"
}

function Format-PlanText {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Plan
    )

    $lines = New-Object Collections.Generic.List[string]
    $lines.Add("Kaynak: $script:SourceRoot")
    $lines.Add("Hedef : $script:DestinationRoot")
    $lines.Add("")
    $lines.Add("Bulunan masaüstü öğesi: $(@($Plan).Count)")
    $lines.Add("")

    foreach ($entry in $Plan) {
        $relativeDestination = $entry.Destination.Substring(
            $script:DestinationRoot.Length
        ).TrimStart("\")
        $lines.Add(("{0} -> {1}" -f $entry.Name, $relativeDestination))
    }

    if (@($Plan).Count -eq 0) {
        $lines.Add("Düzenlenecek yeni masaüstü öğesi yok.")
    }

    return $lines -join [Environment]::NewLine
}

function Start-OrganizerGui {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    [Windows.Forms.Application]::EnableVisualStyles()

    $form = New-Object Windows.Forms.Form
    $form.Text = "Masaüstü Proje ve Tür Düzenleyici"
    $form.StartPosition = "CenterScreen"
    $form.Size = New-Object Drawing.Size(850, 600)
    $form.MinimumSize = New-Object Drawing.Size(760, 520)
    $form.Font = New-Object Drawing.Font("Segoe UI", 10)

    $title = New-Object Windows.Forms.Label
    $title.Text = "Masaüstü Proje ve Tür Düzenleyici"
    $title.Font = New-Object Drawing.Font("Segoe UI Semibold", 16)
    $title.AutoSize = $true
    $title.Location = New-Object Drawing.Point(20, 16)
    $form.Controls.Add($title)

    $description = New-Object Windows.Forms.Label
    $description.Text = (
        "Projeleri Belgeler\GitHub_Projeleri, bağımsız dosyaları " +
        "Belgeler\DOSYA_KOKENLI_ARSIV altında toplar. Dosya silmez."
    )
    $description.AutoSize = $true
    $description.Location = New-Object Drawing.Point(22, 54)
    $form.Controls.Add($description)

    $outputBox = New-Object Windows.Forms.TextBox
    $outputBox.Multiline = $true
    $outputBox.ReadOnly = $true
    $outputBox.ScrollBars = "Both"
    $outputBox.WordWrap = $false
    $outputBox.Anchor = "Top,Bottom,Left,Right"
    $outputBox.Location = New-Object Drawing.Point(24, 88)
    $outputBox.Size = New-Object Drawing.Size(785, 400)
    $form.Controls.Add($outputBox)

    $refreshButton = New-Object Windows.Forms.Button
    $refreshButton.Text = "Önizlemeyi Yenile"
    $refreshButton.Anchor = "Bottom,Left"
    $refreshButton.Location = New-Object Drawing.Point(24, 505)
    $refreshButton.Size = New-Object Drawing.Size(150, 36)
    $form.Controls.Add($refreshButton)

    $moveButton = New-Object Windows.Forms.Button
    $moveButton.Text = "Masaüstünü Düzenle"
    $moveButton.Anchor = "Bottom,Left"
    $moveButton.Location = New-Object Drawing.Point(184, 505)
    $moveButton.Size = New-Object Drawing.Size(165, 36)
    $form.Controls.Add($moveButton)

    $undoButton = New-Object Windows.Forms.Button
    $undoButton.Text = "Son İşlemi Geri Al"
    $undoButton.Anchor = "Bottom,Left"
    $undoButton.Location = New-Object Drawing.Point(359, 505)
    $undoButton.Size = New-Object Drawing.Size(165, 36)
    $form.Controls.Add($undoButton)

    $documentsButton = New-Object Windows.Forms.Button
    $documentsButton.Text = "Belgeleri Yönet"
    $documentsButton.Anchor = "Bottom,Left"
    $documentsButton.Location = New-Object Drawing.Point(534, 505)
    $documentsButton.Size = New-Object Drawing.Size(115, 36)
    $form.Controls.Add($documentsButton)

    $openButton = New-Object Windows.Forms.Button
    $openButton.Text = "Hedef Klasörü Aç"
    $openButton.Anchor = "Bottom,Right"
    $openButton.Location = New-Object Drawing.Point(659, 505)
    $openButton.Size = New-Object Drawing.Size(150, 36)
    $form.Controls.Add($openButton)

    $script:CurrentPlan = @()

    $refreshAction = {
        try {
            $script:CurrentPlan = @(Get-DesktopPlan)
            $outputBox.Text = Format-PlanText -Plan $script:CurrentPlan
        }
        catch {
            $outputBox.Text = "HATA: $($_.Exception.Message)"
        }
    }

    $refreshButton.Add_Click($refreshAction)

    $moveButton.Add_Click({
        try {
            $script:CurrentPlan = @(Get-DesktopPlan)
            if ($script:CurrentPlan.Count -eq 0) {
                [Windows.Forms.MessageBox]::Show(
                    "Düzenlenecek yeni masaüstü öğesi yok.",
                    "Bilgi",
                    "OK",
                    "Information"
                ) | Out-Null
                return
            }

            $answer = [Windows.Forms.MessageBox]::Show(
                (
                    "$($script:CurrentPlan.Count) masaüstü öğesi " +
                    "Belgeler klasörüne taşınacak.`n`nDevam edilsin mi?"
                ),
                "Taşıma onayı",
                "YesNo",
                "Question"
            )

            if ($answer -ne [Windows.Forms.DialogResult]::Yes) {
                return
            }

            $form.UseWaitCursor = $true
            $result = Invoke-DesktopMove -Plan $script:CurrentPlan
            $form.UseWaitCursor = $false

            $outputBox.Text = (
                "İşlem tamamlandı.`r`n" +
                "Taşınan: $($result.Summary.Moved)`r`n" +
                "Atlanan: $($result.Summary.Skipped)`r`n" +
                "Hata: $($result.Summary.Errors)`r`n`r`n" +
                "Kayıt: $($result.ManifestPath)"
            )
        }
        catch {
            $form.UseWaitCursor = $false
            [Windows.Forms.MessageBox]::Show(
                $_.Exception.Message,
                "Hata",
                "OK",
                "Error"
            ) | Out-Null
        }
    })

    $undoButton.Add_Click({
        try {
            $answer = [Windows.Forms.MessageBox]::Show(
                "Son taşıma işlemi masaüstüne geri alınacak. Devam edilsin mi?",
                "Geri alma onayı",
                "YesNo",
                "Warning"
            )

            if ($answer -ne [Windows.Forms.DialogResult]::Yes) {
                return
            }

            $form.UseWaitCursor = $true
            $result = Invoke-UndoLastMove
            $form.UseWaitCursor = $false

            $outputBox.Text = (
                "Geri alma tamamlandı.`r`n" +
                "Geri getirilen: $($result.Summary.Restored)`r`n" +
                "Atlanan: $($result.Summary.Skipped)`r`n" +
                "Hata: $($result.Summary.Errors)`r`n`r`n" +
                "Kayıt: $($result.ManifestPath)"
            )
        }
        catch {
            $form.UseWaitCursor = $false
            [Windows.Forms.MessageBox]::Show(
                $_.Exception.Message,
                "Hata",
                "OK",
                "Error"
            ) | Out-Null
        }
    })

    $documentsButton.Add_Click({
        $documentsScript = Join-Path `
            $PSScriptRoot `
            "Belgeler_Duzenleyici.ps1"

        if (-not (Test-Path -LiteralPath $documentsScript -PathType Leaf)) {
            [Windows.Forms.MessageBox]::Show(
                "Belgeler düzenleyici modülü bulunamadı: $documentsScript",
                "Eksik modül",
                "OK",
                "Error"
            ) | Out-Null
            return
        }

        $powershellPath = Join-Path $PSHOME "powershell.exe"
        $arguments = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-STA",
            "-WindowStyle", "Hidden",
            "-File", "`"$documentsScript`"",
            "-Mode", "Gui"
        )

        Start-Process -FilePath $powershellPath `
            -ArgumentList $arguments
    })

    $openButton.Add_Click({
        if (-not (Test-Path -LiteralPath $script:DestinationRoot)) {
            New-Item -ItemType Directory `
                -Path $script:DestinationRoot -Force | Out-Null
        }
        Start-Process explorer.exe -ArgumentList $script:DestinationRoot
    })

    $form.Add_Shown($refreshAction)
    [void]$form.ShowDialog()
}

$script:SourceRoot = $SourceRoot
$script:DestinationRoot = $DestinationRoot

switch ($Mode) {
    "Gui" {
        Assert-SafeRoots
        Start-OrganizerGui
    }

    "Preview" {
        $plan = @(Get-DesktopPlan)
        Format-PlanText -Plan $plan
    }

    "Move" {
        $plan = @(Get-DesktopPlan)

        if ($plan.Count -eq 0) {
            Write-Host "Düzenlenecek yeni masaüstü öğesi yok."
            exit 0
        }

        if (-not $NonInteractive) {
            Write-Host (Format-PlanText -Plan $plan)
            $answer = Read-Host "Taşıma yapılsın mı? (EVET yazın)"
            if ($answer -cne "EVET") {
                Write-Host "İşlem iptal edildi."
                exit 0
            }
        }

        $result = Invoke-DesktopMove -Plan $plan
        $result.Summary | Format-List

        if ($result.Summary.Errors -gt 0) {
            exit 2
        }
    }

    "UndoLast" {
        if (-not $NonInteractive) {
            $answer = Read-Host "Son taşıma geri alınsın mı? (EVET yazın)"
            if ($answer -cne "EVET") {
                Write-Host "İşlem iptal edildi."
                exit 0
            }
        }

        $result = Invoke-UndoLastMove
        $result.Summary | Format-List

        if ($result.Summary.Errors -gt 0) {
            exit 2
        }
    }
}
