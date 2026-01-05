$cred = Get-Credential
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.notes-backup" | Out-Null
$cred | Export-Clixml "$env:USERPROFILE\.notes-backup\smtp-cred.xml"
