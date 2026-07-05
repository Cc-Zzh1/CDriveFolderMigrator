Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "Stop"
$script:Lang = "zh"
$script:I18n = @{
    zh = @{
        WindowTitle = "C 盘文件夹迁移工具"
        SourceLabel = "源目录（C 盘）："
        TargetLabel = "目标根目录："
        Browse = "选择..."
        EstimateSize = "预估大小"
        OpenTarget = "打开目标"
        RemoveBackup = "删除临时备份"
        Restore = "还原迁移"
        Migrate = "迁移所选"
        Language = "Language:"
        Tips = "建议：先关闭相关程序。不要迁移 Windows、Program Files、DriverStore、整个 AppData。适合迁移游戏存档、浏览器用户数据、明确的大型软件配置目录。"
        Ready1 = "工具已启动。"
        Ready2 = "选择源目录和目标根目录后，先点预估大小，再点迁移所选。"
        PickSource = "选择要迁移的 C 盘文件夹"
        PickTarget = "选择目标根目录（建议 E 盘）"
        SourceMissing = "源目录不存在。"
        StartSize = "开始统计："
        Size = "大小："
        EstimateFailed = "预估失败"
        ConfirmMigrateTitle = "确认迁移"
        ConfirmMigrate = "即将复制目录、移动原目录并创建目录联接。请确认相关程序已关闭。继续吗？"
        MigrateDone = "迁移完成。"
        Done = "完成"
        MigrateFailed = "迁移失败"
        Failed = "失败："
        RestoreDone = "还原操作完成。"
        RestoreFailed = "还原失败"
        RestoreDialogTitle = "选择要还原的迁移记录"
        RestoreSelected = "还原选中项"
        Cancel = "取消"
        ConfirmRestoreTitle = "确认还原"
        ConfirmRestore = "即将删除 C 盘联接入口，并把 E 盘真实目录移动回原路径。请确认相关程序已关闭。继续吗？"
        OriginalPath = "原路径："
        MigratedPath = "现路径："
        ReadmeFile = "迁移说明.txt"
        ReportCsvFile = "迁移来源清单.csv"
        LogFile = "迁移记录.txt"
    }
    en = @{
        WindowTitle = "C Drive Folder Migrator"
        SourceLabel = "Source (C drive):"
        TargetLabel = "Target root:"
        Browse = "Browse..."
        EstimateSize = "Estimate"
        OpenTarget = "Open Target"
        RemoveBackup = "Delete temp backup"
        Restore = "Restore"
        Migrate = "Migrate"
        Language = "语言："
        Tips = "Tip: close related apps first. Do not migrate Windows, Program Files, DriverStore, or the whole AppData folder. Best for game saves, browser profiles, and known large app data folders."
        Ready1 = "Tool started."
        Ready2 = "Choose source and target root, then click Estimate before Migrate."
        PickSource = "Select a C drive folder to migrate"
        PickTarget = "Select target root folder, preferably on another drive"
        SourceMissing = "Source folder does not exist."
        StartSize = "Calculating size: "
        Size = "Size: "
        EstimateFailed = "Estimate failed"
        ConfirmMigrateTitle = "Confirm migration"
        ConfirmMigrate = "This will copy the folder, move the original folder, and create a junction. Make sure related apps are closed. Continue?"
        MigrateDone = "Migration completed."
        Done = "Done"
        MigrateFailed = "Migration failed"
        Failed = "Failed: "
        RestoreDone = "Restore completed."
        RestoreFailed = "Restore failed"
        RestoreDialogTitle = "Select a migration record to restore"
        RestoreSelected = "Restore Selected"
        Cancel = "Cancel"
        ConfirmRestoreTitle = "Confirm restore"
        ConfirmRestore = "This will remove the C drive junction and move the real folder back from the target drive. Make sure related apps are closed. Continue?"
        OriginalPath = "Original path: "
        MigratedPath = "Migrated path: "
        ReadmeFile = "migration-notes.txt"
        ReportCsvFile = "migration-sources.csv"
        LogFile = "migration-log.txt"
    }
}

function T {
    param([string]$Key)
    if ($script:I18n[$script:Lang].ContainsKey($Key)) { return $script:I18n[$script:Lang][$Key] }
    return $Key
}

function Test-IsReparsePoint {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force
    return [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

function Get-DirectorySize {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0L }
    $sum = Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum
    if ($sum.Sum) { return [int64]$sum.Sum }
    return 0L
}

function Format-Bytes {
    param([int64]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Get-SafeName {
    param([string]$Name)
    return ($Name -replace '[\\/:*?"<>|]', '_')
}

function Add-Log {
    param([string]$Message)
    $time = Get-Date -Format "HH:mm:ss"
    $script:LogBox.AppendText("[$time] $Message`r`n")
    $script:LogBox.SelectionStart = $script:LogBox.TextLength
    $script:LogBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Pick-Folder {
    param([string]$Description, [string]$InitialDirectory)
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $true
    if ($InitialDirectory -and (Test-Path -LiteralPath $InitialDirectory)) {
        $dialog.SelectedPath = $InitialDirectory
    }
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    }
    return $null
}

function Get-MigrationReportPath {
    param([string]$TargetRoot)
    New-Item -ItemType Directory -Force -Path $TargetRoot | Out-Null
    return Join-Path $TargetRoot (T "ReportCsvFile")
}

function Get-MigrationReportCandidates {
    param([string]$TargetRoot)
    New-Item -ItemType Directory -Force -Path $TargetRoot | Out-Null
    $names = @(
        (T "ReportCsvFile"),
        $script:I18n.zh.ReportCsvFile,
        $script:I18n.en.ReportCsvFile
    ) | Select-Object -Unique
    foreach ($name in $names) {
        Join-Path $TargetRoot $name
    }
}

function Append-MigrationReport {
    param(
        [string]$TargetRoot,
        [string]$Source,
        [string]$Target,
        [string]$Size,
        [string]$Note
    )
    $csv = Get-MigrationReportPath -TargetRoot $TargetRoot
    $row = [pscustomobject]@{
        Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        OriginalPath = $Source
        MigratedPath = $Target
        Size = $Size
        Note = $Note
    }
    if (Test-Path -LiteralPath $csv) {
        $row | Export-Csv -LiteralPath $csv -NoTypeInformation -Append -Encoding UTF8
    } else {
        $row | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
    }

    $logPath = Join-Path $TargetRoot (T "LogFile")
    if ($script:Lang -eq "en") {
        $logLines = @(
            "",
            "[$($row.Time)]",
            "Original path: $Source",
            "Migrated path: $Target",
            "Size: $Size",
            "Note: $Note"
        )
    } else {
        $logLines = @(
            "",
            "[$($row.Time)]",
            "原路径：$Source",
            "现路径：$Target",
            "大小：$Size",
            "备注：$Note"
        )
    }
    $logLines | Add-Content -LiteralPath $logPath -Encoding UTF8
}

function Get-RestoreBackupCandidates {
    param(
        [string]$Source,
        [string]$Note
    )

    $sourceFull = [System.IO.Path]::GetFullPath($Source).TrimEnd('\')
    $parent = Split-Path -Parent $sourceFull
    $leaf = Split-Path -Leaf $sourceFull
    $candidatePaths = New-Object System.Collections.Generic.List[string]

    if ($Note -match 'backup kept:\s*(.+)$') {
        $candidatePaths.Add($matches[1].Trim())
    }

    if (Test-Path -LiteralPath $parent) {
        $pattern = "$leaf`_backup_migrated_*"
        Get-ChildItem -LiteralPath $parent -Directory -Force -Filter $pattern -ErrorAction SilentlyContinue | ForEach-Object {
            $candidatePaths.Add($_.FullName)
        }
    }

    $safeNameRegex = "^$([regex]::Escape($leaf))_backup_migrated_\d{8}_\d{6}$"
    $safePaths = New-Object System.Collections.Generic.List[string]
    foreach ($path in ($candidatePaths | Select-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) { continue }
        $full = [System.IO.Path]::GetFullPath($path).TrimEnd('\')
        $item = Get-Item -LiteralPath $full -Force
        if (-not $item.PSIsContainer) { continue }
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        if (-not ([System.IO.Path]::GetFullPath((Split-Path -Parent $full)).TrimEnd('\').Equals($parent, [System.StringComparison]::OrdinalIgnoreCase))) { continue }
        if ($item.Name -notmatch $safeNameRegex) { continue }
        $safePaths.Add($full)
    }
    return $safePaths
}

function Remove-RestoreBackups {
    param(
        [string]$Source,
        [string]$Note
    )

    $backups = @(Get-RestoreBackupCandidates -Source $Source -Note $Note)
    $removed = 0
    foreach ($backup in $backups) {
        Add-Log "删除还原后残留的临时备份：$backup"
        try {
            Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction Stop
            $removed++
        } catch {
            Add-Log "临时备份删除失败，请手动检查：$backup"
        }
    }
    if ($removed -gt 0) {
        Add-Log "已删除临时备份：$removed 个"
    }
}

function Restore-Migration {
    param(
        [string]$Source,
        [string]$Target,
        [string]$TargetRoot,
        [string]$Note
    )

    if ([string]::IsNullOrWhiteSpace($Source) -or [string]::IsNullOrWhiteSpace($Target)) {
        throw "还原记录缺少原路径或现路径。"
    }

    $sourceFull = [System.IO.Path]::GetFullPath($Source).TrimEnd('\')
    $targetFull = [System.IO.Path]::GetFullPath($Target).TrimEnd('\')
    if (-not $sourceFull.StartsWith("C:\", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "原路径必须在 C 盘。"
    }
    if ($targetFull.StartsWith("C:\", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "现路径不能在 C 盘。"
    }
    if (-not (Test-Path -LiteralPath $sourceFull)) {
        throw "原路径不存在：$sourceFull"
    }
    if (-not (Test-IsReparsePoint -Path $sourceFull)) {
        throw "原路径不是目录联接。为避免误删真实目录，已停止。"
    }
    if (-not (Test-Path -LiteralPath $targetFull)) {
        throw "现路径不存在：$targetFull"
    }

    $sourceItem = Get-Item -LiteralPath $sourceFull -Force
    $junctionTargets = @($sourceItem.Target)
    if ($junctionTargets.Count -gt 0) {
        $matched = $false
        foreach ($jt in $junctionTargets) {
            if ([System.IO.Path]::GetFullPath($jt).TrimEnd('\').Equals($targetFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                $matched = $true
            }
        }
        if (-not $matched) {
            throw "联接目标和记录里的现路径不一致。为避免误操作，已停止。"
        }
    }

    $parent = Split-Path -Parent $sourceFull
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    $size = Get-DirectorySize -Path $targetFull
    Add-Log "准备还原：$sourceFull"
    Add-Log "真实目录：$targetFull"
    Add-Log "大小：$(Format-Bytes $size)"
    Add-Log "删除 C 盘联接入口..."
    cmd /c rmdir "$sourceFull" | Out-Null
    if (Test-Path -LiteralPath $sourceFull) {
        throw "删除联接入口失败：$sourceFull"
    }

    Add-Log "把真实目录移动回 C 盘原路径..."
    Move-Item -LiteralPath $targetFull -Destination $sourceFull -ErrorAction Stop
    if (-not (Test-Path -LiteralPath $sourceFull) -or (Test-IsReparsePoint -Path $sourceFull)) {
        throw "还原后原路径状态异常，请手动检查。"
    }

    Remove-RestoreBackups -Source $sourceFull -Note $Note
    Append-MigrationReport -TargetRoot $TargetRoot -Source $sourceFull -Target $targetFull -Size (Format-Bytes $size) -Note "restored to original path"
    Add-Log "还原完成：$sourceFull"
}

function Show-RestoreDialog {
    param([string]$TargetRoot)

    if ([string]::IsNullOrWhiteSpace($TargetRoot)) { throw "请选择目标根目录。" }
    $csv = Get-MigrationReportCandidates -TargetRoot $TargetRoot | Where-Object {
        Test-Path -LiteralPath $_
    } | Select-Object -First 1
    if (-not $csv) {
        if ($script:Lang -eq "en") {
            throw "No migration source list found under: $TargetRoot"
        }
        throw "没有找到迁移来源清单：$TargetRoot"
    }
    $records = Import-Csv -LiteralPath $csv | Where-Object {
        $_.OriginalPath -and $_.MigratedPath -and $_.Note -notmatch '^restored'
    } | Sort-Object Time -Descending
    if (-not $records -or $records.Count -eq 0) {
        throw "迁移来源清单里没有可还原记录。"
    }

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = T "RestoreDialogTitle"
    $dialog.Size = New-Object System.Drawing.Size(980, 520)
    $dialog.StartPosition = "CenterParent"
    $dialog.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Location = New-Object System.Drawing.Point(12, 12)
    $grid.Size = New-Object System.Drawing.Size(940, 400)
    $grid.Anchor = "Top,Bottom,Left,Right"
    $grid.ReadOnly = $true
    $grid.SelectionMode = "FullRowSelect"
    $grid.MultiSelect = $false
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.AutoSizeColumnsMode = "Fill"
    $grid.DataSource = [System.Collections.ArrayList]@($records)
    $dialog.Controls.Add($grid)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = T "RestoreSelected"
    $ok.Location = New-Object System.Drawing.Point(735, 430)
    $ok.Size = New-Object System.Drawing.Size(105, 34)
    $ok.Anchor = "Right,Bottom"
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dialog.Controls.Add($ok)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = T "Cancel"
    $cancel.Location = New-Object System.Drawing.Point(850, 430)
    $cancel.Size = New-Object System.Drawing.Size(105, 34)
    $cancel.Anchor = "Right,Bottom"
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dialog.Controls.Add($cancel)
    $dialog.AcceptButton = $ok
    $dialog.CancelButton = $cancel

    if ($dialog.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }
    if ($grid.SelectedRows.Count -lt 1) { throw "没有选中记录。" }
    $record = $grid.SelectedRows[0].DataBoundItem

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "$((T "ConfirmRestore"))`r`n`r`n$((T "OriginalPath"))$($record.OriginalPath)`r`n$((T "MigratedPath"))$($record.MigratedPath)",
        (T "ConfirmRestoreTitle"),
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    Restore-Migration -Source $record.OriginalPath -Target $record.MigratedPath -TargetRoot $TargetRoot -Note $record.Note
}

function Write-Readme {
    param([string]$TargetRoot)
    $path = Join-Path $TargetRoot (T "ReadmeFile")
    if ($script:Lang -eq "en") {
        $lines = @(
            "C Drive Folder Migration Notes",
            "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
            "",
            "This tool copies the selected C drive folder to the target drive, then replaces the original path with a directory junction.",
            "Applications can keep using the original C drive path, while the real data is stored on the target drive.",
            "",
            "Restore manually:",
            "1. Close the related app.",
            "2. Remove the junction folder at the original C drive path.",
            "3. Move the matching target folder back to the original C drive path.",
            "",
            "Migration records:",
            "- CSV list: $($script:I18n.en.ReportCsvFile)",
            "- Text log: $($script:I18n.en.LogFile)",
            "",
            "Warning: if an uninstaller is set to delete user data, it may follow the junction and delete the real data on the target drive."
        )
    } else {
        $lines = @(
            "C 盘文件夹迁移说明",
            "生成时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
            "",
            "这个工具会把所选 C 盘文件夹复制到目标盘，然后把原路径替换为目录联接。",
            "程序继续访问原 C 盘路径，真实数据写入目标盘。",
            "",
            "还原方式：",
            "1. 关闭相关程序。",
            "2. 删除原 C 盘路径的联接文件夹。",
            "3. 把目标盘对应目录剪切回原 C 盘路径。",
            "",
            "迁移记录：",
            "- 表格清单：$($script:I18n.zh.ReportCsvFile)",
            "- 文本记录：$($script:I18n.zh.LogFile)",
            "",
            "注意：卸载程序如果选择删除用户数据，可能会沿着联接删除目标盘数据。"
        )
    }
    $lines | Set-Content -LiteralPath $path -Encoding UTF8
}

function Start-Migration {
    param(
        [string]$Source,
        [string]$TargetRoot,
        [bool]$RemoveBackup
    )

    if ([string]::IsNullOrWhiteSpace($Source) -or -not (Test-Path -LiteralPath $Source)) {
        throw "源目录不存在。"
    }
    if ([string]::IsNullOrWhiteSpace($TargetRoot)) {
        throw "请选择目标根目录。"
    }
    $sourceFull = [System.IO.Path]::GetFullPath($Source).TrimEnd('\')
    if (-not $sourceFull.StartsWith("C:\", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "这个工具只迁移 C 盘目录。"
    }
    if (Test-IsReparsePoint -Path $sourceFull) {
        throw "源目录已经是联接/符号链接，不需要重复迁移。"
    }

    $targetRootFull = [System.IO.Path]::GetFullPath($TargetRoot).TrimEnd('\')
    if ($targetRootFull.StartsWith("C:\", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "目标目录不能仍在 C 盘。"
    }

    $leaf = Split-Path -Leaf $sourceFull
    if ([string]::IsNullOrWhiteSpace($leaf)) { $leaf = "MigratedFolder" }
    $target = Join-Path $targetRootFull (Get-SafeName -Name $leaf)
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    if (Test-Path -LiteralPath $target) {
        $target = Join-Path $targetRootFull "$(Get-SafeName -Name $leaf)_$stamp"
    }

    $parent = Split-Path -Parent $sourceFull
    $backup = Join-Path $parent "$leaf`_backup_migrated_$stamp"

    Add-Log "源目录：$sourceFull"
    Add-Log "目标目录：$target"
    Add-Log "开始统计大小..."
    $sourceSize = Get-DirectorySize -Path $sourceFull
    Add-Log "源目录大小：$(Format-Bytes $sourceSize)"

    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Write-Readme -TargetRoot $targetRootFull

    Add-Log "开始复制，使用 robocopy..."
    & robocopy $sourceFull $target /MIR /COPY:DAT /DCOPY:DAT /R:2 /W:1 /XJ | Out-Null
    $code = $LASTEXITCODE
    if ($code -ge 8) {
        throw "robocopy 失败，退出码：$code"
    }

    Add-Log "复制完成，开始校验大小..."
    $targetSize = Get-DirectorySize -Path $target
    Add-Log "目标目录大小：$(Format-Bytes $targetSize)"
    if ([math]::Abs($sourceSize - $targetSize) -gt 10MB) {
        throw "大小差异超过 10MB，停止迁移。源：$(Format-Bytes $sourceSize)，目标：$(Format-Bytes $targetSize)"
    }

    Add-Log "移动原目录为临时备份..."
    Move-Item -LiteralPath $sourceFull -Destination $backup -ErrorAction Stop

    Add-Log "创建目录联接..."
    $mklinkOutput = cmd /c mklink /J "$sourceFull" "$target"
    if (-not (Test-Path -LiteralPath $sourceFull) -or -not (Test-IsReparsePoint -Path $sourceFull)) {
        Move-Item -LiteralPath $backup -Destination $sourceFull -ErrorAction SilentlyContinue
        throw "联接创建失败，已尝试还原原目录。$mklinkOutput"
    }

    $note = "junction created"
    if ($RemoveBackup) {
        Add-Log "删除临时备份..."
        Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction Stop
        $note = "junction created; backup removed"
    } else {
        Add-Log "临时备份保留：$backup"
        $note = "junction created; backup kept: $backup"
    }

    Append-MigrationReport -TargetRoot $targetRootFull -Source $sourceFull -Target $target -Size (Format-Bytes $targetSize) -Note $note
    Add-Log "迁移完成。原路径现在指向：$target"
}

$form = New-Object System.Windows.Forms.Form
$form.Text = T "WindowTitle"
$form.Size = New-Object System.Drawing.Size(980, 650)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(920, 610)

$font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
$form.Font = $font

$sourceLabel = New-Object System.Windows.Forms.Label
$sourceLabel.Text = T "SourceLabel"
$sourceLabel.Location = New-Object System.Drawing.Point(14, 18)
$sourceLabel.Size = New-Object System.Drawing.Size(120, 24)
$form.Controls.Add($sourceLabel)

$sourceText = New-Object System.Windows.Forms.TextBox
$sourceText.Location = New-Object System.Drawing.Point(135, 16)
$sourceText.Size = New-Object System.Drawing.Size(700, 24)
$form.Controls.Add($sourceText)

$sourceButton = New-Object System.Windows.Forms.Button
$sourceButton.Text = T "Browse"
$sourceButton.Location = New-Object System.Drawing.Point(850, 14)
$sourceButton.Size = New-Object System.Drawing.Size(90, 30)
$sourceButton.Add_Click({
    $picked = Pick-Folder -Description (T "PickSource") -InitialDirectory "C:\Users\Administrator\AppData"
    if ($picked) { $sourceText.Text = $picked }
})
$form.Controls.Add($sourceButton)

$targetLabel = New-Object System.Windows.Forms.Label
$targetLabel.Text = T "TargetLabel"
$targetLabel.Location = New-Object System.Drawing.Point(14, 58)
$targetLabel.Size = New-Object System.Drawing.Size(120, 24)
$form.Controls.Add($targetLabel)

$targetText = New-Object System.Windows.Forms.TextBox
$targetText.Location = New-Object System.Drawing.Point(135, 56)
$targetText.Size = New-Object System.Drawing.Size(700, 24)
$targetText.Text = "E:\AppDataMigrated"
$form.Controls.Add($targetText)

$targetButton = New-Object System.Windows.Forms.Button
$targetButton.Text = T "Browse"
$targetButton.Location = New-Object System.Drawing.Point(850, 54)
$targetButton.Size = New-Object System.Drawing.Size(90, 30)
$targetButton.Add_Click({
    $picked = Pick-Folder -Description (T "PickTarget") -InitialDirectory "E:\"
    if ($picked) { $targetText.Text = $picked }
})
$form.Controls.Add($targetButton)

$scanButton = New-Object System.Windows.Forms.Button
$scanButton.Text = T "EstimateSize"
$scanButton.Location = New-Object System.Drawing.Point(135, 96)
$scanButton.Size = New-Object System.Drawing.Size(115, 36)
$scanButton.Add_Click({
    try {
        if (-not (Test-Path -LiteralPath $sourceText.Text)) { throw (T "SourceMissing") }
        Add-Log "$((T "StartSize"))$($sourceText.Text)"
        $size = Get-DirectorySize -Path $sourceText.Text
        Add-Log "$((T "Size"))$(Format-Bytes $size)"
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, (T "EstimateFailed"), "OK", "Warning") | Out-Null
    }
})
$form.Controls.Add($scanButton)

$openTargetButton = New-Object System.Windows.Forms.Button
$openTargetButton.Text = T "OpenTarget"
$openTargetButton.Location = New-Object System.Drawing.Point(265, 96)
$openTargetButton.Size = New-Object System.Drawing.Size(115, 36)
$openTargetButton.Add_Click({
    if (-not (Test-Path -LiteralPath $targetText.Text)) {
        New-Item -ItemType Directory -Force -Path $targetText.Text | Out-Null
    }
    Start-Process explorer.exe $targetText.Text
})
$form.Controls.Add($openTargetButton)

$check = New-Object System.Windows.Forms.CheckBox
$check.Text = T "RemoveBackup"
$check.Location = New-Object System.Drawing.Point(395, 104)
$check.Size = New-Object System.Drawing.Size(245, 24)
$check.Checked = $false
$form.Controls.Add($check)

$restoreButton = New-Object System.Windows.Forms.Button
$restoreButton.Text = T "Restore"
$restoreButton.Location = New-Object System.Drawing.Point(665, 96)
$restoreButton.Size = New-Object System.Drawing.Size(125, 36)
$restoreButton.Add_Click({
    $restoreButton.Enabled = $false
    try {
        Show-RestoreDialog -TargetRoot $targetText.Text
        [System.Windows.Forms.MessageBox]::Show((T "RestoreDone"), (T "Done"), "OK", "Information") | Out-Null
    } catch {
        Add-Log "$((T "RestoreFailed"))：$($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, (T "RestoreFailed"), "OK", "Error") | Out-Null
    } finally {
        $restoreButton.Enabled = $true
    }
})
$form.Controls.Add($restoreButton)

$migrateButton = New-Object System.Windows.Forms.Button
$migrateButton.Text = T "Migrate"
$migrateButton.Location = New-Object System.Drawing.Point(805, 96)
$migrateButton.Size = New-Object System.Drawing.Size(135, 36)
$migrateButton.BackColor = [System.Drawing.Color]::FromArgb(230, 244, 255)
$migrateButton.Add_Click({
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        (T "ConfirmMigrate"),
        (T "ConfirmMigrateTitle"),
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    $migrateButton.Enabled = $false
    try {
        Start-Migration -Source $sourceText.Text -TargetRoot $targetText.Text -RemoveBackup $check.Checked
        [System.Windows.Forms.MessageBox]::Show((T "MigrateDone"), (T "Done"), "OK", "Information") | Out-Null
    } catch {
        Add-Log "$((T "Failed"))$($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, (T "MigrateFailed"), "OK", "Error") | Out-Null
    } finally {
        $migrateButton.Enabled = $true
    }
})
$form.Controls.Add($migrateButton)

$tips = New-Object System.Windows.Forms.Label
$tips.Text = T "Tips"
$tips.Location = New-Object System.Drawing.Point(14, 175)
$tips.Size = New-Object System.Drawing.Size(925, 42)
$tips.ForeColor = [System.Drawing.Color]::FromArgb(90, 90, 90)
$form.Controls.Add($tips)

$script:LogBox = New-Object System.Windows.Forms.TextBox
$script:LogBox.Location = New-Object System.Drawing.Point(16, 225)
$script:LogBox.Size = New-Object System.Drawing.Size(925, 340)
$script:LogBox.Anchor = "Top,Bottom,Left,Right"
$script:LogBox.Multiline = $true
$script:LogBox.ScrollBars = "Vertical"
$script:LogBox.ReadOnly = $true
$script:LogBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$form.Controls.Add($script:LogBox)

$languageLabel = New-Object System.Windows.Forms.Label
$languageLabel.Text = T "Language"
$languageLabel.Location = New-Object System.Drawing.Point(14, 145)
$languageLabel.Size = New-Object System.Drawing.Size(80, 24)
$form.Controls.Add($languageLabel)

$languageCombo = New-Object System.Windows.Forms.ComboBox
$languageCombo.Location = New-Object System.Drawing.Point(95, 142)
$languageCombo.Size = New-Object System.Drawing.Size(160, 28)
$languageCombo.DropDownStyle = "DropDownList"
[void]$languageCombo.Items.Add("中文")
[void]$languageCombo.Items.Add("English")
$languageCombo.SelectedIndex = 0
$form.Controls.Add($languageCombo)

function Apply-Language {
    $form.Text = T "WindowTitle"
    $sourceLabel.Text = T "SourceLabel"
    $targetLabel.Text = T "TargetLabel"
    $sourceButton.Text = T "Browse"
    $targetButton.Text = T "Browse"
    $scanButton.Text = T "EstimateSize"
    $openTargetButton.Text = T "OpenTarget"
    $check.Text = T "RemoveBackup"
    $restoreButton.Text = T "Restore"
    $migrateButton.Text = T "Migrate"
    $languageLabel.Text = T "Language"
    $tips.Text = T "Tips"
}

$languageCombo.Add_SelectedIndexChanged({
    if ($languageCombo.SelectedIndex -eq 1) { $script:Lang = "en" } else { $script:Lang = "zh" }
    Apply-Language
    Add-Log "Language: $($languageCombo.SelectedItem)"
})

Add-Log (T "Ready1")
Add-Log (T "Ready2")

[void]$form.ShowDialog()




