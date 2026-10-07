param(
    [Parameter(Mandatory = $true)][long]$RunId,
    [ValidateSet('Status', 'Logs', 'Artifacts')][string]$Mode = 'Status'
)
$ErrorActionPreference = 'Stop'
if ($RunId -le 0) { throw 'A positive GitHub Actions run id is required.' }
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$destination = Join-Path $workspace ".tools/verification/$RunId"
$api = "https://api.github.com/repos/dabok407/to-do-list/actions/runs/$RunId"
$headers = @{ Accept = 'application/vnd.github+json' }
if ($Mode -ne 'Status') {
    $credentialLines = "protocol=https`nhost=github.com`n`n" | git credential fill
    $secretLine = $credentialLines | Where-Object { $_.StartsWith('password=') }
    if (-not $secretLine) { throw 'GitHub credentials are unavailable.' }
    $headers.Authorization = 'Bearer ' + $secretLine.Substring(9)
}
if ($Mode -eq 'Status') {
    $jobs = Invoke-RestMethod "$api/jobs" -Headers $headers -TimeoutSec 30
    $jobs.jobs | ForEach-Object {
        [pscustomobject]@{
            id = $_.id; name = $_.name; status = $_.status; conclusion = $_.conclusion
            current = ($_.steps | Where-Object status -eq 'in_progress' | Select-Object -ExpandProperty name)
            failed = ($_.steps | Where-Object conclusion -eq 'failure' | Select-Object -ExpandProperty name)
        }
    } | ConvertTo-Json -Depth 4
    exit
}
New-Item -ItemType Directory -Path $destination -Force | Out-Null
if ($Mode -eq 'Logs') {
    $jobs = Invoke-RestMethod "$api/jobs" -Headers $headers -TimeoutSec 30
    foreach ($job in $jobs.jobs | Where-Object status -eq 'completed') {
        $log = Join-Path $destination "$($job.id).log"
        Invoke-WebRequest "https://api.github.com/repos/dabok407/to-do-list/actions/jobs/$($job.id)/logs" -Headers $headers -OutFile $log -TimeoutSec 60
        Write-Output "$($job.name): $log"
        Select-String -Path $log -Pattern '##\[error\]|EXCEPTION CAUGHT|Test failed|TEST FAILED|tests passed|TEST SUCCEEDED|BACKGROUND_NOTIFICATION_OK|REBOOT_NOTIFICATION_OK|WIDGET_.*_OK|DEEP_LINK_OK' | Select-Object -Last 15 | ForEach-Object { $_.Line }
    }
} else {
    $artifacts = Invoke-RestMethod "$api/artifacts" -Headers $headers -TimeoutSec 30
    foreach ($artifact in $artifacts.artifacts | Where-Object { $_.name -like '*-integration-results' -and -not $_.expired }) {
        $zip = Join-Path $destination "$($artifact.id).zip"
        $folder = Join-Path $destination "$($artifact.id)"
        Invoke-WebRequest $artifact.archive_download_url -Headers $headers -OutFile $zip -TimeoutSec 120
        Expand-Archive -LiteralPath $zip -DestinationPath $folder -Force
        Write-Output "$($artifact.name): $folder"
    }
}
