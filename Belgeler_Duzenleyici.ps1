[CmdletBinding()]
param(
    [ValidateSet(
        "Gui",
        "Preview",
        "Organize",
        "DedupePreview",
        "Dedupe",
        "WastePreview",
        "WasteCleanup",
        "CleanupPreview",
        "Cleanup",
        "Full",
        "UndoOrganize"
    )]
    [string]$Mode = "Gui",

    [string]$DocumentsRoot = [Environment]::GetFolderPath("MyDocuments"),

    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Öğrenme notu:
# 1. Proje klasörleri tek parça taşınır; iç yapıları bozulmaz.
# 2. Uzantı klasörleri DOSYA_TURU_ARSIVI altında toplanır.
# 3. Yinelenenler yalnız uzantı arşivinde ve SHA-256 birebir aynıysa
#    Geri Dönüşüm Kutusu'na gönderilir.
# 4. Codex, çalışan uygulama, GitHub klonları ve PowerShell profili korunur.

$script:ProtectedTopLevelNames = @(
    "Codex",
    "Masaustu_Duzenlenmis",
    "Masaustu_Duzenleyici_Uygulamasi",
    "WindowsPowerShell",
    "GitHub_Projeleri",
    "PROJE_ARSIVI",
    "DOSYA_TURU_ARSIVI",
    "ARSIV_VE_YEDEKLER",
    "GENEL_KLASORLER",
    "_BELGELER_DUZENLEME_KAYITLARI",
    "pclog.CSV"
)

$script:TypeFolderNames = @(
    "BAT", "BIN", "CACHE", "CFG", "CMD", "CS", "CSPROJ", "CSS",
    "CSV", "DBF", "DBT", "DLL", "DOCX", "EDITORCONFIG", "EML",
    "EXE", "FMT", "GITIGNORE", "GITKEEP", "HTML", "ICO", "IDX",
    "INI", "IPYNB", "ISS", "JPEG", "JS", "JSON", "LNK", "LOG",
    "MANIFEST", "MBOX", "MD", "MJS", "MTIMES", "NDJSON", "ODB",
    "ODT", "PACK", "PDF", "PMAP", "PNG", "PROPS", "PS1", "PST",
    "PY", "PYC", "PYW", "R", "RDF", "REV", "RTF", "SAMPLE", "SDV",
    "SH", "SPEC", "SQLITE3", "TAG", "TARGETS", "TEXT", "THM",
    "TOML", "TXT", "UP2DATE", "UZANTISIZ", "XBA", "XCU", "XLB",
    "XLC", "XLS", "XLSX", "XML", "YAML", "YML", "ZIP"
)

function Get-NormalizedPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $full = [IO.Path]::GetFullPath(
        [Environment]::ExpandEnvironmentVariables($Path)
    )
    if ($full.Length -gt 3) {
        return $full.TrimEnd("\")
    }
    return $full
}

function Get-SafeName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $safe = $Name -replace '[<>:"/\\|?*]+', "_"
    $safe = $safe -replace "\s+", "_"
    $safe = $safe.Trim(" ", ".", "_")
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return "Genel_Proje"
    }
    return $safe
}

function Get-ExtensionFolder {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileName
    )

    $extension = [IO.Path]::GetExtension($FileName)
    if ([string]::IsNullOrWhiteSpace($extension)) {
        return "UZANTISIZ"
    }
    return $extension.TrimStart(".").ToUpperInvariant()
}

function Test-TopLevelGitRepository {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return Test-Path -LiteralPath (Join-Path $Path ".git") `
        -PathType Container
}

function Get-ItemRoute {
    param(
        [Parameter(Mandatory = $true)]
        [IO.FileSystemInfo]$Item
    )

    $projectRoot = Join-Path $script:DocumentsRoot "PROJE_ARSIVI"
    $typeRoot = Join-Path $script:DocumentsRoot "DOSYA_TURU_ARSIVI"
    $backupRoot = Join-Path $script:DocumentsRoot "ARSIV_VE_YEDEKLER"
    $generalRoot = Join-Path $script:DocumentsRoot "GENEL_KLASORLER"

    $name = $Item.Name
    $lower = $name.ToLowerInvariant()

    if ($Item.PSIsContainer) {
        if (
            $name -match '^(?i:UzantiDuzenleyici|Uzanti_Duzenleyici)'
        ) {
            return [pscustomobject]@{
                Category = "ProjectVersion"
                Family = "Dosya_Duzenleyici_GUI"
                Directory = Join-Path `
                    (Join-Path $projectRoot "Dosya_Duzenleyici_GUI") `
                    "Surumler"
            }
        }

        switch -Regex ($name) {
            '^(?i:cv_maker)$' {
                return [pscustomobject]@{
                    Category = "ProjectVersion"
                    Family = "CV_Maker"
                    Directory = Join-Path `
                        (Join-Path $projectRoot "CV_Maker") `
                        "Surumler"
                }
            }
            '^(?i:bulut_proje)$' {
                return [pscustomobject]@{
                    Category = "ProjectVersion"
                    Family = "Bulut_Proje"
                    Directory = Join-Path `
                        (Join-Path $projectRoot "Bulut_Proje") `
                        "Surumler"
                }
            }
            '^(?i:odtü_membs|odtu_membs|odtü_mems|odtu_mems)$' {
                return [pscustomobject]@{
                    Category = "ProjectVersion"
                    Family = "ODTU_MEMS"
                    Directory = Join-Path `
                        (Join-Path $projectRoot "ODTU_MEMS") `
                        "Surumler"
                }
            }
            '^(?i:BAU)$' {
                return [pscustomobject]@{
                    Category = "Project"
                    Family = "BAU"
                    Directory = Join-Path $projectRoot "BAU"
                }
            }
            '^(?i:_YEDEK|DOSYA_ARSIVI)$' {
                return [pscustomobject]@{
                    Category = "Backup"
                    Family = "Arsiv_ve_Yedek"
                    Directory = $backupRoot
                }
            }
            '^(?i:_DUZENLEYICI_KAYITLARI)$' {
                return [pscustomobject]@{
                    Category = "Backup"
                    Family = "Duzenleyici_Kayitlari"
                    Directory = Join-Path `
                        $backupRoot `
                        "Duzenleyici_Kayitlari"
                }
            }
            '^(?i:Downloads|OpenAI_Code_Inbox)$' {
                return [pscustomobject]@{
                    Category = "GeneralFolder"
                    Family = "Genel"
                    Directory = $generalRoot
                }
            }
        }

        if ($script:TypeFolderNames -contains $name.ToUpperInvariant()) {
            return [pscustomobject]@{
                Category = "ExtensionFolder"
                Family = $name.ToUpperInvariant()
                Directory = $typeRoot
            }
        }

        if (Test-TopLevelGitRepository -Path $Item.FullName) {
            $family = Get-SafeName -Name $Item.Name
            return [pscustomobject]@{
                Category = "GitProject"
                Family = $family
                Directory = Join-Path `
                    (Join-Path $projectRoot $family) `
                    "Surumler"
            }
        }

        return [pscustomobject]@{
            Category = "GeneralFolder"
            Family = "Genel"
            Directory = $generalRoot
        }
    }

    if (
        $lower -match (
            "duzenleyici|düzenleyici|bos_klasor|ana_klasore|" +
            "uzanti|extension_sorter|turune_gore"
        )
    ) {
        $extension = Get-ExtensionFolder -FileName $name
        return [pscustomobject]@{
            Category = "ProjectFile"
            Family = "Dosya_Duzenleyici_GUI"
            Directory = Join-Path `
                (Join-Path `
                    (Join-Path $projectRoot "Dosya_Duzenleyici_GUI") `
                    "Bagimsiz_Dosyalar") `
                $extension
        }
    }

    $extensionFolder = Get-ExtensionFolder -FileName $name
    return [pscustomobject]@{
        Category = "ExtensionFile"
        Family = $extensionFolder
        Directory = Join-Path $typeRoot $extensionFolder
    }
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

    $candidate = Join-Path $Directory $Name
    $baseName = [IO.Path]::GetFileNameWithoutExtension($Name)
    $extension = [IO.Path]::GetExtension($Name)
    $counter = 1

    while (
        (Test-Path -LiteralPath $candidate) -or
        $Reserved.Contains($candidate)
    ) {
        $candidate = Join-Path `
            $Directory `
            ("{0}__Belgeler_{1}{2}" -f $baseName, $counter, $extension)
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

    $files = @(
        Get-ChildItem -LiteralPath $Path -File -Recurse -Force `
            -ErrorAction SilentlyContinue -ErrorVariable readProblems
    )

    [long]$totalBytes = 0
    foreach ($file in $files) {
        $totalBytes += [long]$file.Length
    }

    return [pscustomobject]@{
        FileCount = $files.Count
        TotalBytes = $totalBytes
        ReadErrors = @($readProblems).Count
    }
}

function Assert-DocumentsRoot {
    $script:DocumentsRoot = Get-NormalizedPath -Path $script:DocumentsRoot
    if (
        -not (
            Test-Path -LiteralPath $script:DocumentsRoot `
                -PathType Container
        )
    ) {
        throw "Belgeler klasörü bulunamadı: $script:DocumentsRoot"
    }
}

function Get-LongPropertySum {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Items,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName
    )

    [long]$sum = 0
    foreach ($item in $Items) {
        $property = $item.PSObject.Properties[$PropertyName]
        if ($null -ne $property -and $null -ne $property.Value) {
            $sum += [long]$property.Value
        }
    }
    return $sum
}

function Get-OrganizePlan {
    Assert-DocumentsRoot

    $reserved = New-Object `
        "Collections.Generic.HashSet[string]" `
        ([StringComparer]::OrdinalIgnoreCase)

    $items = Get-ChildItem -LiteralPath $script:DocumentsRoot -Force |
        Where-Object {
            $script:ProtectedTopLevelNames -notcontains $_.Name
        } |
        Sort-Object @{ Expression = { -not $_.PSIsContainer } }, Name

    $plan = New-Object Collections.Generic.List[object]

    foreach ($item in $items) {
        $route = Get-ItemRoute -Item $item
        $destination = Get-UniqueDestination `
            -Directory $route.Directory `
            -Name $item.Name `
            -Reserved $reserved

        $isReparse = (
            $item.Attributes -band [IO.FileAttributes]::ReparsePoint
        ) -ne 0

        $plan.Add([pscustomobject]@{
            Source = $item.FullName
            Destination = $destination
            Name = $item.Name
            ItemType = if ($item.PSIsContainer) { "Folder" } else { "File" }
            Category = $route.Category
            Family = $route.Family
            IsReparsePoint = $isReparse
            SizeBytes = if ($item.PSIsContainer) {
                0
            }
            else {
                [long]$item.Length
            }
        })
    }

    return $plan.ToArray()
}

function Get-LogRoot {
    $path = Join-Path `
        $script:DocumentsRoot `
        "_BELGELER_DUZENLEME_KAYITLARI"
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
    return $path
}

function Write-JsonSummary {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Summary,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $Summary |
        ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-Organize {
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
        $quarantinePath = ""
        $hashBefore = ""
        $hashAfter = ""
        [long]$sizeBytes = [long]$entry.SizeBytes
        $fileCount = if ($entry.ItemType -eq "File") { 1 } else { 0 }

        try {
            if (-not (Test-Path -LiteralPath $entry.Source)) {
                $status = "SkippedMissing"
            }
            elseif ($entry.IsReparsePoint) {
                $status = "SkippedReparsePoint"
            }
            else {
                $destinationParent = Split-Path -Parent $entry.Destination
                if (-not (Test-Path -LiteralPath $destinationParent)) {
                    New-Item -ItemType Directory `
                        -Path $destinationParent -Force | Out-Null
                }

                if ($entry.ItemType -eq "File") {
                    $hashBefore = (
                        Get-FileHash -LiteralPath $entry.Source `
                            -Algorithm SHA256
                    ).Hash

                    Move-Item -LiteralPath $entry.Source `
                        -Destination $entry.Destination

                    $hashAfter = (
                        Get-FileHash -LiteralPath $entry.Destination `
                            -Algorithm SHA256
                    ).Hash

                    if ($hashBefore -ne $hashAfter) {
                        throw "Dosya SHA-256 doğrulaması başarısız."
                    }
                }
                else {
                    $before = Get-DirectoryStatistics -Path $entry.Source
                    if ($before.ReadErrors -gt 0) {
                        throw (
                            "Klasör tam okunamadığı için taşınmadı. " +
                            "Okuma hatası: $($before.ReadErrors)"
                        )
                    }

                    $fileCount = $before.FileCount
                    $sizeBytes = $before.TotalBytes

                    Move-Item -LiteralPath $entry.Source `
                        -Destination $entry.Destination

                    $after = Get-DirectoryStatistics `
                        -Path $entry.Destination

                    if (
                        $after.ReadErrors -gt 0 -or
                        $before.FileCount -ne $after.FileCount -or
                        $before.TotalBytes -ne $after.TotalBytes
                    ) {
                        throw (
                            "Klasör taşıma sonrası dosya sayısı/boyut " +
                            "doğrulaması başarısız."
                        )
                    }
                }

                $status = "Moved"
            }
        }
        catch {
            $status = "Error"
            $errorMessage = $_.Exception.Message

            if (
                -not (Test-Path -LiteralPath $entry.Source) -and
                (Test-Path -LiteralPath $entry.Destination)
            ) {
                try {
                    $sourceParent = Split-Path -Parent $entry.Source
                    if (-not (Test-Path -LiteralPath $sourceParent)) {
                        New-Item -ItemType Directory `
                            -Path $sourceParent -Force | Out-Null
                    }
                    Move-Item -LiteralPath $entry.Destination `
                        -Destination $entry.Source
                    $errorMessage += " Kaynak konuma geri alındı."
                }
                catch {
                    $errorMessage += (
                        " Otomatik geri alma başarısız: " +
                        $_.Exception.Message
                    )
                }
            }
        }

        $records.Add([pscustomobject][ordered]@{
            RunId = $runId
            Timestamp = (Get-Date).ToString("o")
            Source = $entry.Source
            Destination = $entry.Destination
            ItemType = $entry.ItemType
            Category = $entry.Category
            Family = $entry.Family
            Status = $status
            SizeBytes = $sizeBytes
            FileCount = $fileCount
            HashBefore = $hashBefore
            HashAfter = $hashAfter
            Error = $errorMessage
        })
    }

    $logRoot = Get-LogRoot
    $manifestPath = Join-Path `
        $logRoot `
        "organize_manifest_$runId.csv"
    $summaryPath = Join-Path `
        $logRoot `
        "organize_summary_$runId.json"

    $records.ToArray() |
        Export-Csv -LiteralPath $manifestPath `
            -NoTypeInformation -Encoding UTF8

    $summary = @{
        RunId = $runId
        Operation = "Organize"
        Total = $records.Count
        Moved = @($records | Where-Object Status -eq "Moved").Count
        Skipped = @(
            $records |
                Where-Object Status -like "Skipped*"
        ).Count
        Errors = @($records | Where-Object Status -eq "Error").Count
        ManifestPath = $manifestPath
        FinishedAt = (Get-Date).ToString("o")
    }
    Write-JsonSummary -Summary $summary -Path $summaryPath

    return [pscustomobject]$summary
}

function Get-DuplicatePlan {
    Assert-DocumentsRoot

    $typeRoot = Join-Path $script:DocumentsRoot "DOSYA_TURU_ARSIVI"
    if (-not (Test-Path -LiteralPath $typeRoot -PathType Container)) {
        return @()
    }

    $files = @(
        Get-ChildItem -LiteralPath $typeRoot -File -Recurse -Force `
            -ErrorAction SilentlyContinue |
            Where-Object { $_.Length -gt 0 }
    )

    $sizeGroups = @(
        $files |
            Group-Object Length |
            Where-Object Count -gt 1
    )

    $hashGroups = @{}
    $candidateCounter = 0

    foreach ($sizeGroup in $sizeGroups) {
        foreach ($file in $sizeGroup.Group) {
            $candidateCounter++
            if (($candidateCounter % 1000) -eq 0) {
                Write-Progress `
                    -Activity "SHA-256 yinelenen taraması" `
                    -Status "$candidateCounter aday incelendi"
            }

            try {
                $hash = (
                    Get-FileHash -LiteralPath $file.FullName `
                        -Algorithm SHA256
                ).Hash
                $key = "{0}|{1}" -f $file.Length, $hash

                if (-not $hashGroups.ContainsKey($key)) {
                    $hashGroups[$key] = New-Object `
                        Collections.Generic.List[object]
                }

                $hashGroups[$key].Add([pscustomobject]@{
                    Path = $file.FullName
                    Length = [long]$file.Length
                    Hash = $hash
                    LastWriteTime = $file.LastWriteTime
                })
            }
            catch {
                Write-Warning (
                    "Hash alınamadı, dosya tekilleştirilmedi: " +
                    "$($file.FullName) | $($_.Exception.Message)"
                )
            }
        }
    }

    Write-Progress -Activity "SHA-256 yinelenen taraması" -Completed

    $plan = New-Object Collections.Generic.List[object]

    foreach ($key in $hashGroups.Keys) {
        # Windows PowerShell 5.1, generic List[object] değerini @(...)
        # ile diziye çevirirken bazı sistemlerde bağlayıcı hatası verebilir.
        # ToArray() açık ve kararlı bir dönüşüm sağlar.
        $group = $hashGroups[$key].ToArray()
        if ($group.Count -lt 2) {
            continue
        }

        $sorted = @(
            $group |
                Sort-Object `
                    @{ Expression = { $_.Path.Length } }, `
                    @{ Expression = { $_.LastWriteTime } }, `
                    Path
        )

        $keeper = $sorted[0]
        foreach ($duplicate in $sorted | Select-Object -Skip 1) {
            $plan.Add([pscustomobject]@{
                KeepPath = $keeper.Path
                DuplicatePath = $duplicate.Path
                SizeBytes = $duplicate.Length
                Sha256 = $duplicate.Hash
                Action = "SendToRecycleBin"
            })
        }
    }

    return $plan.ToArray()
}

function Invoke-Dedupe {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Plan
    )

    $runId = Get-Date -Format "yyyyMMdd_HHmmss"
    $logRoot = Get-LogRoot
    $planPath = Join-Path $logRoot "duplicate_plan_$runId.csv"
    $resultPath = Join-Path $logRoot "duplicate_result_$runId.csv"
    $summaryPath = Join-Path $logRoot "duplicate_summary_$runId.json"

    $Plan |
        Export-Csv -LiteralPath $planPath `
            -NoTypeInformation -Encoding UTF8

    Add-Type -AssemblyName Microsoft.VisualBasic
    $records = New-Object Collections.Generic.List[object]

    foreach ($entry in $Plan) {
        $status = ""
        $errorMessage = ""

        try {
            if (-not (Test-Path -LiteralPath $entry.KeepPath -PathType Leaf)) {
                $status = "SkippedKeeperMissing"
            }
            elseif (
                -not (
                    Test-Path -LiteralPath $entry.DuplicatePath `
                        -PathType Leaf
                )
            ) {
                $status = "SkippedDuplicateMissing"
            }
            else {
                $current = Get-Item -LiteralPath $entry.DuplicatePath
                if ([long]$current.Length -ne [long]$entry.SizeBytes) {
                    throw "Dosya boyutu planlamadan sonra değişti."
                }

                $currentHash = (
                    Get-FileHash -LiteralPath $entry.DuplicatePath `
                        -Algorithm SHA256
                ).Hash

                if ($currentHash -ne $entry.Sha256) {
                    throw "SHA-256 planlamadan sonra değişti."
                }

                # Hidden/System/ReadOnly desktop.ini kopyalarında Windows'un
                # Geri Dönüşüm Kutusu API'si bekleyebilir. Bu özel dosyaları
                # silmek yerine kayıt klasöründeki karantinaya taşırız.
                $blockingAttributes = (
                    [IO.FileAttributes]::Hidden -bor
                    [IO.FileAttributes]::System -bor
                    [IO.FileAttributes]::ReadOnly
                )

                if (
                    (
                        $current.Attributes -band $blockingAttributes
                    ) -ne 0
                ) {
                    $quarantineRoot = Join-Path `
                        (Join-Path $logRoot "DUPLIKE_KARANTINA") `
                        $runId
                    if (-not (Test-Path -LiteralPath $quarantineRoot)) {
                        New-Item -ItemType Directory `
                            -Path $quarantineRoot -Force | Out-Null
                    }

                    $tag = [Guid]::NewGuid().ToString("N").Substring(0, 8)
                    $quarantinePath = Join-Path `
                        $quarantineRoot `
                        ("{0}_{1}" -f $tag, $current.Name)

                    Move-Item -LiteralPath $entry.DuplicatePath `
                        -Destination $quarantinePath
                    $status = "Quarantined"
                }
                else {
                    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                        $entry.DuplicatePath,
                        [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                        [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin,
                        [Microsoft.VisualBasic.FileIO.UICancelOption]::ThrowException
                    )

                    if (Test-Path -LiteralPath $entry.DuplicatePath) {
                        throw (
                            "Dosya Geri Dönüşüm Kutusu'na gönderilemedi."
                        )
                    }

                    $status = "Recycled"
                }
            }
        }
        catch {
            $status = "Error"
            $errorMessage = $_.Exception.Message
        }

        $records.Add([pscustomobject][ordered]@{
            RunId = $runId
            Timestamp = (Get-Date).ToString("o")
            KeepPath = $entry.KeepPath
            DuplicatePath = $entry.DuplicatePath
            SizeBytes = $entry.SizeBytes
            Sha256 = $entry.Sha256
            Status = $status
            QuarantinePath = $quarantinePath
            Error = $errorMessage
        })
    }

    $records.ToArray() |
        Export-Csv -LiteralPath $resultPath `
            -NoTypeInformation -Encoding UTF8

    $summary = @{
        RunId = $runId
        Operation = "Dedupe"
        Planned = $Plan.Count
        Recycled = @($records | Where-Object Status -eq "Recycled").Count
        Quarantined = @(
            $records |
                Where-Object Status -eq "Quarantined"
        ).Count
        BytesRemovedFromArchive = Get-LongPropertySum `
            -Items @(
                $records |
                    Where-Object Status -in @("Recycled", "Quarantined")
            ) `
            -PropertyName "SizeBytes"
        Skipped = @(
            $records |
                Where-Object Status -like "Skipped*"
        ).Count
        Errors = @($records | Where-Object Status -eq "Error").Count
        PlanPath = $planPath
        ResultPath = $resultPath
        FinishedAt = (Get-Date).ToString("o")
    }
    Write-JsonSummary -Summary $summary -Path $summaryPath

    return [pscustomobject]$summary
}

function Get-EmptyFolderPlan {
    Assert-DocumentsRoot

    $managedRoots = @(
        "PROJE_ARSIVI",
        "DOSYA_TURU_ARSIVI",
        "ARSIV_VE_YEDEKLER",
        "GENEL_KLASORLER"
    ) |
        ForEach-Object { Join-Path $script:DocumentsRoot $_ } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Container }

    $emptyFolders = New-Object Collections.Generic.List[string]

    foreach ($root in $managedRoots) {
        $directories = @(
            Get-ChildItem -LiteralPath $root -Directory -Recurse -Force `
                -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.FullName -notmatch '(?i)\\\.git(\\|$)'
                } |
                Sort-Object { $_.FullName.Length } -Descending
        )

        foreach ($directory in $directories) {
            # Altında hiç dosya bulunmayan klasör zincirinin tamamını plana
            # alırız. Uygulama en derinden başlayarak sildiği için önce çocuk,
            # sonra boşalan üst klasör güvenle kaldırılır.
            $childFile = Get-ChildItem -LiteralPath $directory.FullName `
                -File -Recurse -Force -ErrorAction SilentlyContinue |
                Select-Object -First 1

            if ($null -eq $childFile) {
                $emptyFolders.Add($directory.FullName)
            }
        }
    }

    return $emptyFolders.ToArray()
}

function Get-WasteFolderPlan {
    Assert-DocumentsRoot

    $recursiveRoots = @(
        "PROJE_ARSIVI",
        "GENEL_KLASORLER",
        "Masaustu_Duzenlenmis"
    ) |
        ForEach-Object { Join-Path $script:DocumentsRoot $_ } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Container }

    $wasteNames = @(
        ".venv",
        "venv",
        "__pycache__",
        ".pytest_cache",
        ".mypy_cache",
        ".ruff_cache",
        ".ipynb_checkpoints",
        "node_modules",
        ".cache",
        ".tox",
        "htmlcov"
    )

    $candidatePaths = New-Object Collections.Generic.List[string]

    foreach ($root in $recursiveRoots) {
        Get-ChildItem -LiteralPath $root -Directory -Recurse -Force `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $wasteNames -contains $_.Name.ToLowerInvariant() -and
                $_.FullName -notmatch '(?i)\\\.git(\\|$)'
            } |
            ForEach-Object {
                $candidatePaths.Add($_.FullName)
            }
    }

    foreach ($typeWasteName in @("CACHE", "PYC")) {
        $typeWastePath = Join-Path `
            (Join-Path $script:DocumentsRoot "DOSYA_TURU_ARSIVI") `
            $typeWasteName
        if (Test-Path -LiteralPath $typeWastePath -PathType Container) {
            $candidatePaths.Add($typeWastePath)
        }
    }

    # Bir .venv seçilmişse onun içindeki __pycache__ klasörlerini ayrıca
    # planlamayız. Yalnız en üst atık kökü işleme alınır.
    $selected = New-Object Collections.Generic.List[string]
    foreach ($path in ($candidatePaths | Sort-Object Length, { $_ })) {
        $insideSelected = $false
        foreach ($parent in $selected) {
            $prefix = $parent.TrimEnd("\") + "\"
            if (
                $path.StartsWith(
                    $prefix,
                    [StringComparison]::OrdinalIgnoreCase
                )
            ) {
                $insideSelected = $true
                break
            }
        }

        if (-not $insideSelected) {
            $selected.Add($path)
        }
    }

    $plan = New-Object Collections.Generic.List[object]
    foreach ($path in $selected) {
        $statistics = Get-DirectoryStatistics -Path $path
        $plan.Add([pscustomobject]@{
            Path = $path
            Name = Split-Path -Leaf $path
            FileCount = $statistics.FileCount
            SizeBytes = $statistics.TotalBytes
            ReadErrors = $statistics.ReadErrors
            Action = "SendFolderToRecycleBin"
        })
    }

    return $plan.ToArray()
}

function Invoke-WasteFolderCleanup {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Plan
    )

    $runId = Get-Date -Format "yyyyMMdd_HHmmss"
    $records = New-Object Collections.Generic.List[object]
    Add-Type -AssemblyName Microsoft.VisualBasic

    $allowedRoots = @(
        "PROJE_ARSIVI",
        "GENEL_KLASORLER",
        "Masaustu_Duzenlenmis",
        "DOSYA_TURU_ARSIVI"
    ) |
        ForEach-Object {
            Get-NormalizedPath -Path (
                Join-Path $script:DocumentsRoot $_
            )
        }

    foreach ($entry in $Plan) {
        $status = ""
        $errorMessage = ""

        try {
            $candidate = Get-NormalizedPath -Path $entry.Path
            $allowed = $false

            foreach ($root in $allowedRoots) {
                $prefix = $root.TrimEnd("\") + "\"
                if (
                    $candidate.StartsWith(
                        $prefix,
                        [StringComparison]::OrdinalIgnoreCase
                    )
                ) {
                    $allowed = $true
                    break
                }
            }

            if (-not $allowed) {
                throw "Atık klasör güvenli yönetilen kökün dışında."
            }

            if ($entry.ReadErrors -gt 0) {
                throw (
                    "Klasör tam okunamadığı için kaldırılmadı. " +
                    "Okuma hatası: $($entry.ReadErrors)"
                )
            }

            if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
                $status = "SkippedMissing"
            }
            else {
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
                    $candidate,
                    [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                    [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin,
                    [Microsoft.VisualBasic.FileIO.UICancelOption]::ThrowException
                )

                if (Test-Path -LiteralPath $candidate) {
                    throw "Atık klasör Geri Dönüşüm Kutusu'na gönderilemedi."
                }

                $status = "RecycledWasteFolder"
            }
        }
        catch {
            $status = "Error"
            $errorMessage = $_.Exception.Message
        }

        $records.Add([pscustomobject][ordered]@{
            RunId = $runId
            Timestamp = (Get-Date).ToString("o")
            Path = $entry.Path
            FileCount = $entry.FileCount
            SizeBytes = $entry.SizeBytes
            Status = $status
            Error = $errorMessage
        })
    }

    $logRoot = Get-LogRoot
    $resultPath = Join-Path `
        $logRoot `
        "waste_folder_result_$runId.csv"
    $summaryPath = Join-Path `
        $logRoot `
        "waste_folder_summary_$runId.json"

    $records.ToArray() |
        Export-Csv -LiteralPath $resultPath `
            -NoTypeInformation -Encoding UTF8

    $summary = @{
        RunId = $runId
        Operation = "WasteFolderCleanup"
        Planned = $Plan.Count
        Recycled = @(
            $records |
                Where-Object Status -eq "RecycledWasteFolder"
        ).Count
        FilesRecycled = Get-LongPropertySum `
            -Items @(
                $records |
                    Where-Object Status -eq "RecycledWasteFolder"
            ) `
            -PropertyName "FileCount"
        BytesRecycled = Get-LongPropertySum `
            -Items @(
                $records |
                    Where-Object Status -eq "RecycledWasteFolder"
            ) `
            -PropertyName "SizeBytes"
        Skipped = @(
            $records |
                Where-Object Status -like "Skipped*"
        ).Count
        Errors = @($records | Where-Object Status -eq "Error").Count
        ResultPath = $resultPath
        FinishedAt = (Get-Date).ToString("o")
    }
    Write-JsonSummary -Summary $summary -Path $summaryPath

    return [pscustomobject]$summary
}

function Invoke-EmptyFolderCleanup {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Plan
    )

    $runId = Get-Date -Format "yyyyMMdd_HHmmss"
    $records = New-Object Collections.Generic.List[object]

    foreach ($path in ($Plan | Sort-Object Length -Descending)) {
        $status = ""
        $errorMessage = ""

        try {
            if (-not (Test-Path -LiteralPath $path -PathType Container)) {
                $status = "SkippedMissing"
            }
            else {
                $child = Get-ChildItem -LiteralPath $path `
                    -Force -ErrorAction Stop |
                    Select-Object -First 1

                if ($null -ne $child) {
                    $status = "SkippedNotEmpty"
                }
                else {
                    Remove-Item -LiteralPath $path -Force
                    $status = "RemovedEmpty"
                }
            }
        }
        catch {
            $status = "Error"
            $errorMessage = $_.Exception.Message
        }

        $records.Add([pscustomobject][ordered]@{
            RunId = $runId
            Timestamp = (Get-Date).ToString("o")
            Path = $path
            Status = $status
            Error = $errorMessage
        })
    }

    $logRoot = Get-LogRoot
    $resultPath = Join-Path `
        $logRoot `
        "empty_folder_result_$runId.csv"
    $summaryPath = Join-Path `
        $logRoot `
        "empty_folder_summary_$runId.json"

    $records.ToArray() |
        Export-Csv -LiteralPath $resultPath `
            -NoTypeInformation -Encoding UTF8

    $summary = @{
        RunId = $runId
        Operation = "CleanupEmptyFolders"
        Planned = $Plan.Count
        Removed = @(
            $records |
                Where-Object Status -eq "RemovedEmpty"
        ).Count
        Skipped = @(
            $records |
                Where-Object Status -like "Skipped*"
        ).Count
        Errors = @($records | Where-Object Status -eq "Error").Count
        ResultPath = $resultPath
        FinishedAt = (Get-Date).ToString("o")
    }
    Write-JsonSummary -Summary $summary -Path $summaryPath

    return [pscustomobject]$summary
}

function Invoke-UndoLastOrganize {
    Assert-DocumentsRoot

    $logRoot = Get-LogRoot
    $manifest = Get-ChildItem -LiteralPath $logRoot `
        -Filter "organize_manifest_*.csv" -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($null -eq $manifest) {
        throw "Geri alınabilecek düzenleme manifesti bulunamadı."
    }

    $rows = @(Import-Csv -LiteralPath $manifest.FullName)
    [array]::Reverse($rows)
    $runId = Get-Date -Format "yyyyMMdd_HHmmss"
    $records = New-Object Collections.Generic.List[object]

    foreach ($row in $rows) {
        if ($row.Status -ne "Moved") {
            continue
        }

        $status = ""
        $errorMessage = ""

        try {
            if (-not (Test-Path -LiteralPath $row.Destination)) {
                $status = "SkippedMissing"
            }
            elseif (Test-Path -LiteralPath $row.Source) {
                $status = "SkippedSourceOccupied"
            }
            else {
                $parent = Split-Path -Parent $row.Source
                if (-not (Test-Path -LiteralPath $parent)) {
                    New-Item -ItemType Directory `
                        -Path $parent -Force | Out-Null
                }
                Move-Item -LiteralPath $row.Destination `
                    -Destination $row.Source
                $status = "Restored"
            }
        }
        catch {
            $status = "Error"
            $errorMessage = $_.Exception.Message
        }

        $records.Add([pscustomobject][ordered]@{
            RunId = $runId
            Source = $row.Destination
            Destination = $row.Source
            Status = $status
            Error = $errorMessage
        })
    }

    $resultPath = Join-Path `
        $logRoot `
        "undo_organize_result_$runId.csv"
    $records.ToArray() |
        Export-Csv -LiteralPath $resultPath `
            -NoTypeInformation -Encoding UTF8

    return [pscustomobject]@{
        RunId = $runId
        Restored = @($records | Where-Object Status -eq "Restored").Count
        Skipped = @(
            $records |
                Where-Object Status -like "Skipped*"
        ).Count
        Errors = @($records | Where-Object Status -eq "Error").Count
        ResultPath = $resultPath
    }
}

function Format-OrganizePlan {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Plan
    )

    $lines = New-Object Collections.Generic.List[string]
    $lines.Add("Belgeler: $script:DocumentsRoot")
    $lines.Add("Düzenlenecek üst düzey öğe: $($Plan.Count)")
    $lines.Add("")

    foreach ($entry in $Plan) {
        $relativeDestination = $entry.Destination.Substring(
            $script:DocumentsRoot.Length
        ).TrimStart("\")
        $lines.Add("$($entry.Name) -> $relativeDestination")
    }

    if ($Plan.Count -eq 0) {
        $lines.Add("Düzenlenecek yeni üst düzey öğe yok.")
    }

    return $lines -join [Environment]::NewLine
}

function Start-DocumentsOrganizerGui {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [Windows.Forms.Application]::EnableVisualStyles()

    $form = New-Object Windows.Forms.Form
    $form.Text = "Belgeler Proje, Tür ve Yinelenen Düzenleyici"
    $form.StartPosition = "CenterScreen"
    $form.Size = New-Object Drawing.Size(900, 620)
    $form.MinimumSize = New-Object Drawing.Size(800, 540)
    $form.Font = New-Object Drawing.Font("Segoe UI", 10)

    $title = New-Object Windows.Forms.Label
    $title.Text = "Belgeler Proje, Tür ve Yinelenen Düzenleyici"
    $title.Font = New-Object Drawing.Font("Segoe UI Semibold", 16)
    $title.AutoSize = $true
    $title.Location = New-Object Drawing.Point(20, 15)
    $form.Controls.Add($title)

    $info = New-Object Windows.Forms.Label
    $info.Text = (
        "Projeleri bütün halde, diğer dosyaları uzantıya göre düzenler. " +
        "Birebir aynı yinelenenleri Geri Dönüşüm Kutusu'na gönderir."
    )
    $info.AutoSize = $true
    $info.Location = New-Object Drawing.Point(22, 52)
    $form.Controls.Add($info)

    $output = New-Object Windows.Forms.TextBox
    $output.Multiline = $true
    $output.ReadOnly = $true
    $output.ScrollBars = "Both"
    $output.WordWrap = $false
    $output.Anchor = "Top,Bottom,Left,Right"
    $output.Location = New-Object Drawing.Point(24, 84)
    $output.Size = New-Object Drawing.Size(835, 425)
    $form.Controls.Add($output)

    $previewButton = New-Object Windows.Forms.Button
    $previewButton.Text = "Önizle"
    $previewButton.Anchor = "Bottom,Left"
    $previewButton.Location = New-Object Drawing.Point(24, 525)
    $previewButton.Size = New-Object Drawing.Size(120, 36)
    $form.Controls.Add($previewButton)

    $fullButton = New-Object Windows.Forms.Button
    $fullButton.Text = "Belgeleri Tam Düzenle"
    $fullButton.Anchor = "Bottom,Left"
    $fullButton.Location = New-Object Drawing.Point(154, 525)
    $fullButton.Size = New-Object Drawing.Size(180, 36)
    $form.Controls.Add($fullButton)

    $undoButton = New-Object Windows.Forms.Button
    $undoButton.Text = "Son Taşımayı Geri Al"
    $undoButton.Anchor = "Bottom,Left"
    $undoButton.Location = New-Object Drawing.Point(344, 525)
    $undoButton.Size = New-Object Drawing.Size(180, 36)
    $form.Controls.Add($undoButton)

    $deepButton = New-Object Windows.Forms.Button
    $deepButton.Text = "Projeleri Sadeleştir"
    $deepButton.Anchor = "Bottom,Left"
    $deepButton.Location = New-Object Drawing.Point(534, 525)
    $deepButton.Size = New-Object Drawing.Size(195, 36)
    $form.Controls.Add($deepButton)

    $openButton = New-Object Windows.Forms.Button
    $openButton.Text = "Belgeleri Aç"
    $openButton.Anchor = "Bottom,Right"
    $openButton.Location = New-Object Drawing.Point(739, 525)
    $openButton.Size = New-Object Drawing.Size(120, 36)
    $form.Controls.Add($openButton)

    $refresh = {
        try {
            $plan = @(Get-OrganizePlan)
            $output.Text = Format-OrganizePlan -Plan $plan
        }
        catch {
            $output.Text = "HATA: $($_.Exception.Message)"
        }
    }

    $previewButton.Add_Click($refresh)

    $fullButton.Add_Click({
        $answer = [Windows.Forms.MessageBox]::Show(
            (
                "Belgeler düzenlenecek, SHA-256 birebir aynı yinelenenler " +
                "Geri Dönüşüm Kutusu'na gönderilecek ve boş klasörler " +
                "kaldırılacak.`n`nDevam edilsin mi?"
            ),
            "Tam düzenleme onayı",
            "YesNo",
            "Warning"
        )
        if ($answer -ne [Windows.Forms.DialogResult]::Yes) {
            return
        }

        try {
            $form.UseWaitCursor = $true
            $organize = Invoke-Organize -Plan @(Get-OrganizePlan)
            $duplicates = Invoke-Dedupe -Plan @(Get-DuplicatePlan)
            $waste = Invoke-WasteFolderCleanup `
                -Plan @(Get-WasteFolderPlan)
            $empty = Invoke-EmptyFolderCleanup `
                -Plan @(Get-EmptyFolderPlan)
            $form.UseWaitCursor = $false

            $output.Text = (
                "Tam düzenleme tamamlandı.`r`n" +
                "Taşınan: $($organize.Moved), hata: $($organize.Errors)`r`n" +
                "Geri Dönüşüm Kutusu'na gönderilen yinelenen: " +
                "$($duplicates.Recycled); karantina: " +
                "$($duplicates.Quarantined); hata: " +
                "$($duplicates.Errors)`r`n" +
                "Kaldırılan yeniden üretilebilir atık klasörü: " +
                "$($waste.Recycled), hata: $($waste.Errors)`r`n" +
                "Silinen boş klasör: $($empty.Removed), " +
                "hata: $($empty.Errors)"
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

    $deepButton.Add_Click({
        $deepScript = Join-Path `
            $PSScriptRoot `
            "Sade_Belgeler_Proje_Duzenleyici.ps1"
        if (-not (Test-Path -LiteralPath $deepScript)) {
            [Windows.Forms.MessageBox]::Show(
                "Sade proje düzenleyici bulunamadı: $deepScript",
                "Eksik modül",
                "OK",
                "Error"
            ) | Out-Null
            return
        }

        $answer = [Windows.Forms.MessageBox]::Show(
            (
                "Projeler GitHub_Projeleri altında toplanacak; bağımsız " +
                "EXE ve belgeler tür klasörlerine taşınacak; yeniden " +
                "üretilebilir önbellekler ve açık yedekler Geri Dönüşüm " +
                "Kutusu'na gönderilecek.`n`nDevam edilsin mi?"
            ),
            "Sade proje düzenleme onayı",
            "YesNo",
            "Warning"
        )
        if ($answer -ne [Windows.Forms.DialogResult]::Yes) {
            return
        }

        try {
            $form.UseWaitCursor = $true
            $resultText = (
                & powershell.exe -NoProfile -ExecutionPolicy Bypass `
                    -File $deepScript -Mode Apply 2>&1 |
                    Out-String
            )
            $exitCode = $LASTEXITCODE
            $form.UseWaitCursor = $false
            if ($exitCode -ne 0) {
                throw "Sade düzenleme hata kodu: $exitCode`r`n$resultText"
            }
            $output.Text = "Sade düzenleme tamamlandı.`r`n`r`n$resultText"
        }
        catch {
            $form.UseWaitCursor = $false
            [Windows.Forms.MessageBox]::Show(
                $_.Exception.Message,
                "Sade düzenleme hatası",
                "OK",
                "Error"
            ) | Out-Null
        }
    })

    $undoButton.Add_Click({
        $answer = [Windows.Forms.MessageBox]::Show(
            "Son proje/uzantı taşıması geri alınacak. Devam edilsin mi?",
            "Geri alma onayı",
            "YesNo",
            "Warning"
        )
        if ($answer -ne [Windows.Forms.DialogResult]::Yes) {
            return
        }

        try {
            $result = Invoke-UndoLastOrganize
            $output.Text = (
                "Geri alma tamamlandı.`r`n" +
                "Geri getirilen: $($result.Restored)`r`n" +
                "Atlanan: $($result.Skipped)`r`n" +
                "Hata: $($result.Errors)`r`n" +
                "Kayıt: $($result.ResultPath)"
            )
        }
        catch {
            [Windows.Forms.MessageBox]::Show(
                $_.Exception.Message,
                "Hata",
                "OK",
                "Error"
            ) | Out-Null
        }
    })

    $openButton.Add_Click({
        Start-Process explorer.exe -ArgumentList $script:DocumentsRoot
    })

    $form.Add_Shown($refresh)
    [void]$form.ShowDialog()
}

$script:DocumentsRoot = $DocumentsRoot

switch ($Mode) {
    "Gui" {
        Assert-DocumentsRoot
        Start-DocumentsOrganizerGui
    }
    "Preview" {
        $plan = @(Get-OrganizePlan)
        Format-OrganizePlan -Plan $plan
    }
    "Organize" {
        $plan = @(Get-OrganizePlan)
        if (-not $NonInteractive) {
            Write-Host (Format-OrganizePlan -Plan $plan)
            $answer = Read-Host "Taşıma yapılsın mı? (EVET yazın)"
            if ($answer -cne "EVET") {
                Write-Host "İşlem iptal edildi."
                exit 0
            }
        }
        $result = Invoke-Organize -Plan $plan
        $result | Format-List
        if ($result.Errors -gt 0) { exit 2 }
    }
    "DedupePreview" {
        $plan = @(Get-DuplicatePlan)
        [pscustomobject]@{
            DuplicateFiles = $plan.Count
            ReclaimableBytes = Get-LongPropertySum `
                -Items $plan `
                -PropertyName "SizeBytes"
        } | Format-List
        $plan | Select-Object -First 100 | Format-Table -AutoSize
    }
    "Dedupe" {
        $plan = @(Get-DuplicatePlan)
        if (-not $NonInteractive) {
            Write-Host (
                "$($plan.Count) birebir yinelenen dosya Geri Dönüşüm " +
                "Kutusu'na gönderilecek."
            )
            $answer = Read-Host "Devam edilsin mi? (EVET yazın)"
            if ($answer -cne "EVET") {
                Write-Host "İşlem iptal edildi."
                exit 0
            }
        }
        $result = Invoke-Dedupe -Plan $plan
        $result | Format-List
        if ($result.Errors -gt 0) { exit 2 }
    }
    "WastePreview" {
        $plan = @(Get-WasteFolderPlan)
        [pscustomobject]@{
            WasteFolders = $plan.Count
            Files = Get-LongPropertySum `
                -Items $plan `
                -PropertyName "FileCount"
            Bytes = Get-LongPropertySum `
                -Items $plan `
                -PropertyName "SizeBytes"
        } | Format-List
        $plan | Format-Table -AutoSize
    }
    "WasteCleanup" {
        $plan = @(Get-WasteFolderPlan)
        if (-not $NonInteractive) {
            Write-Host (
                "$($plan.Count) yeniden üretilebilir atık klasörü " +
                "Geri Dönüşüm Kutusu'na gönderilecek."
            )
            $answer = Read-Host "Devam edilsin mi? (EVET yazın)"
            if ($answer -cne "EVET") {
                Write-Host "İşlem iptal edildi."
                exit 0
            }
        }
        $result = Invoke-WasteFolderCleanup -Plan $plan
        $result | Format-List
        if ($result.Errors -gt 0) { exit 2 }
    }
    "CleanupPreview" {
        $plan = @(Get-EmptyFolderPlan)
        Write-Host "Silinebilecek boş klasör: $($plan.Count)"
        $plan
    }
    "Cleanup" {
        $plan = @(Get-EmptyFolderPlan)
        if (-not $NonInteractive) {
            Write-Host "$($plan.Count) boş klasör kaldırılacak."
            $answer = Read-Host "Devam edilsin mi? (EVET yazın)"
            if ($answer -cne "EVET") {
                Write-Host "İşlem iptal edildi."
                exit 0
            }
        }
        $result = Invoke-EmptyFolderCleanup -Plan $plan
        $result | Format-List
        if ($result.Errors -gt 0) { exit 2 }
    }
    "Full" {
        if (-not $NonInteractive) {
            $answer = Read-Host (
                "Taşıma, yinelenenleri Geri Dönüşüm Kutusu'na gönderme " +
                "ve boş klasör temizliği yapılsın mı? (EVET yazın)"
            )
            if ($answer -cne "EVET") {
                Write-Host "İşlem iptal edildi."
                exit 0
            }
        }

        $organize = Invoke-Organize -Plan @(Get-OrganizePlan)
        $dedupe = Invoke-Dedupe -Plan @(Get-DuplicatePlan)
        $waste = Invoke-WasteFolderCleanup `
            -Plan @(Get-WasteFolderPlan)
        $cleanup = Invoke-EmptyFolderCleanup `
            -Plan @(Get-EmptyFolderPlan)

        [pscustomobject]@{
            Moved = $organize.Moved
            OrganizeErrors = $organize.Errors
            DuplicatesRecycled = $dedupe.Recycled
            DuplicatesQuarantined = $dedupe.Quarantined
            DuplicateBytesRemoved = $dedupe.BytesRemovedFromArchive
            DedupeErrors = $dedupe.Errors
            WasteFoldersRecycled = $waste.Recycled
            WasteFilesRecycled = $waste.FilesRecycled
            WasteBytesRecycled = $waste.BytesRecycled
            WasteErrors = $waste.Errors
            EmptyFoldersRemoved = $cleanup.Removed
            CleanupErrors = $cleanup.Errors
        } | Format-List

        if (
            $organize.Errors -gt 0 -or
            $dedupe.Errors -gt 0 -or
            $waste.Errors -gt 0 -or
            $cleanup.Errors -gt 0
        ) {
            exit 2
        }
    }
    "UndoOrganize" {
        if (-not $NonInteractive) {
            $answer = Read-Host "Son taşıma geri alınsın mı? (EVET yazın)"
            if ($answer -cne "EVET") {
                Write-Host "İşlem iptal edildi."
                exit 0
            }
        }
        $result = Invoke-UndoLastOrganize
        $result | Format-List
        if ($result.Errors -gt 0) { exit 2 }
    }
}
