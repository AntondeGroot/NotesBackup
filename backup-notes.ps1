param(
    [Parameter(Mandatory=$true)]
    [string]$ConfigPath
)

function Get-Config($path) {
    if (!(Test-Path $path)) { throw "Config file not found: $path" }
    return Get-Content $path -Raw | ConvertFrom-Json
}

function New-DirectoryIfMissing($path) {
    if (!(Test-Path $path)) { New-Item -ItemType Directory -Path $path | Out-Null }
}

function Write-Log($logFile, $msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Add-Content -Path $logFile -Value $line
}

function Send-StatusEmail($emailCfg, $subject, $body) {
    if (!(Test-Path $emailCfg.credentialFile)) {
        throw "Credential file not found: $($emailCfg.credentialFile)"
    }
    $cred = Import-Clixml $emailCfg.credentialFile

    Send-MailMessage `
        -From $emailCfg.from `
        -To $emailCfg.to `
        -Subject $subject `
        -Body $body `
        -SmtpServer $emailCfg.smtpServer `
        -Port $emailCfg.smtpPort `
        -UseSsl:([bool]$emailCfg.useSsl) `
        -Credential $cred
}

# --------------------------
# Main
# --------------------------
$config = Get-Config $ConfigPath

$notesName    = $config.notesName
$sourceFolder = $config.sourceFolder
$backupFolder = $config.backupFolder
$logFolder    = Join-Path $backupFolder $config.logFolderName

New-DirectoryIfMissing $backupFolder
New-DirectoryIfMissing $logFolder

$logFile = Join-Path $logFolder ("backup-" + (Get-Date -Format "yyyy-MM-dd") + ".log")
$successEmailSent = $false

try {
    Write-Log $logFile "Starting Notes backup..."
    if (!(Test-Path $sourceFolder)) { throw "Source folder does not exist: $sourceFolder" }

    $year  = (Get-Date).ToString("yy")
    $month = (Get-Date).ToString("MM")
    $day   = (Get-Date).ToString("dd")

    $zipName = "$notesName-$year-$month-$day.zip"
    $zipPath = Join-Path $backupFolder $zipName

    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force
        Write-Log $logFile "Removed existing zip: $zipPath"
    }

    Write-Log $logFile "Compressing '$sourceFolder' to '$zipPath'..."
    Compress-Archive -Path (Join-Path $sourceFolder "*") -DestinationPath $zipPath -CompressionLevel Optimal

    if (!(Test-Path $zipPath)) { throw "ZIP file not created: $zipPath" }

    $zipInfo = Get-Item $zipPath
    $sizeMB  = [Math]::Round($zipInfo.Length / 1MB, 2)

    Write-Log $logFile "Backup OK. Zip size: ${sizeMB} MB"

    $subject = "Backup SUCCESSFUL for $notesName ($($zipInfo.Name))"
    $body = @"
Backup completed successfully for: $notesName

Source: $sourceFolder
Destination: $zipPath
Size: ${sizeMB} MB
Time: $(Get-Date)

Log:
$logFile
"@

    Send-StatusEmail $config.email $subject $body
    $successEmailSent = $true
    # Logging after email should not cause a failure email
    try { Write-Log $logFile "Success email sent." } catch { }

    exit 0
}
catch {
    $err = $_.Exception.Message
    Write-Log $logFile "ERROR: $err"

    # If we already sent success, do NOT send failure as well
    if ($successEmailSent) {
        exit 1
    }

    $subject = "Backup FAILED for $notesName ($(Get-Date -Format 'yyyy-MM-dd'))"
    $body = @"
Backup failed for: $notesName

Source: $sourceFolder
Destination folder: $backupFolder
Time: $(Get-Date)

Error:
$err

Log:
$logFile
"@

    try {
        Send-StatusEmail $config.email $subject $body
        Write-Log $logFile "Failure email sent."
    } catch {
        Write-Log $logFile "ERROR sending failure email: $($_.Exception.Message)"
    }

    exit 1
}