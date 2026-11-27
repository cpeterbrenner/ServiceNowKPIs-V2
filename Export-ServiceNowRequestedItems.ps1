<#
.SYNOPSIS
    Extracts Requested Items (sc_req_item) from ServiceNow to CSV (Chrome
    session), then upserts into local Delta Lake / Parquet for Power BI.

.DESCRIPTION
    Daily mode (default) filters (same as incidents):
      - Assignment Group = AAES - North America - User IT Workplace (configurable)
      - Updated (sys_updated_on) >= current date - 7 days
      - Opened By is not Guest Guest

    Downloads land in -DownloadDir as sc_req_item.csv, are processed into
    Delta + Parquet by scripts/process_servicenow_data.py, then the staging CSV
    is archived under Data/archive/.

.PARAMETER Mode
    Daily (default) or Full.

.EXAMPLE
    .\Export-ServiceNowRequestedItems.ps1
#>
[CmdletBinding()]
param(
    [ValidateSet('Daily', 'Full')]
    [string]$Mode = 'Daily',

    [string]$InstanceUrl = 'https://assaabloy.service-now.com',

    [string]$AssignmentGroup = 'AAES - North America - User IT Workplace',

    [string]$DownloadDir = 'C:\Users\pebren\Development\ServiceNow-KPI-V2\Data',

    [string]$PythonExe = 'python',

    [switch]$SkipProcess
)

$ErrorActionPreference = 'Stop'

$fields = @(
    'number'
    'opened_at'
    'incident_state'
    'category'
    'short_description'
    'opened_by'
    'caller_id'
    'assignment_group'
    'active'
    'assigned_to'
    'calendar_duration'
    'business_stc'
    'reopened_time'
    'reopened_by'
    'calendar_stc'
    'u_time_reported'
    'activity_due'
    'u_application'
    'business_duration'
    'u_business_process'
    'contact_type'
    'child_incidents'
    'close_code'
    'closed_at'
    'closed_by'
    'company'
    'u_component'
    'cmdb_ci'
    'u_mi_contact_person'
    'sys_created_on'
    'sys_created_by'
    'u_division'
    'task_effective_number'
    'reassignment_count'
    'u_mi_users_impacted'
    'impact'
    'u_incident_related_to_company'
    'u_mi_business_critical'
    'u_mi_production_environment_affected'
    'location'
    'u_note'
    'u_offering_reassignment_count'
    'u_rpt_open_duration_test'
    'parent_incident'
    'parent'
    'priority'
    'u_received_from'
    'reopen_count'
    'resolved_at'
    'resolved_by'
    'business_service'
    'service_offering'
    'severity'
    'state'
    'subcategory'
    'u_service'
    'u_svc_comp'
    'sys_updated_on'
    'sys_updated_by'
    'sys_mod_count'
    'upon_approval'
    'upon_reject'
    'urgency'
)

$instance = $InstanceUrl.TrimEnd('/')
$repoRoot = $PSScriptRoot

if ($Mode -eq 'Daily') {
    $updatedOnOrAfter = (Get-Date).Date.AddDays(-7)
    $updatedOnOrAfterStr = $updatedOnOrAfter.ToString('yyyy-MM-dd HH:mm:ss')
    $query = [uri]::EscapeDataString(
        "assignment_group.name=$AssignmentGroup^sys_updated_on>=$updatedOnOrAfterStr^opened_by.name!=Guest Guest^ORDERBYnumber"
    )
    Write-Host "Daily filter: assignment_group='$AssignmentGroup'; sys_updated_on >= $updatedOnOrAfterStr; opened_by != Guest Guest"
}
else {
    $currentMonthStart = Get-Date -Year (Get-Date).Year -Month (Get-Date).Month -Day 1 -Hour 0 -Minute 0 -Second 0
    $openedOnOrAfter = $currentMonthStart.AddMonths(-24)
    $openedOnOrAfterStr = $openedOnOrAfter.ToString('yyyy-MM-dd HH:mm:ss')
    $query = [uri]::EscapeDataString(
        "assignment_group.name=$AssignmentGroup^opened_at>=$openedOnOrAfterStr^opened_by.name!=Guest Guest^ORDERBYnumber"
    )
    Write-Host "Full filter: assignment_group='$AssignmentGroup'; opened_at >= $openedOnOrAfterStr; opened_by != Guest Guest"
}

$exportUrl = "$instance/sc_req_item_list.do?CSV&sysparm_query=$query&sysparm_fields=$($fields -join ',')"

$chromeCandidates = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
    "$env:LocalAppData\Google\Chrome\Application\chrome.exe"
)
$chrome = $chromeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chrome) {
    $chrome = (Get-Command chrome.exe -ErrorAction SilentlyContinue).Source
}
if (-not $chrome) {
    throw 'Google Chrome was not found. Install Chrome or update the paths in this script.'
}

Write-Host 'Opening ServiceNow in Chrome so you can sign in (skip if already signed in)...'
Start-Process -FilePath $chrome -ArgumentList "$instance/sp"
Read-Host 'Once the ServiceNow portal has loaded and you are signed in, press Enter to start the export'

if (-not (Test-Path $DownloadDir)) {
    New-Item -ItemType Directory -Path $DownloadDir -Force | Out-Null
}

$downloadsFolder = Join-Path $env:USERPROFILE 'Downloads'
$before = @{}
Get-ChildItem -Path $downloadsFolder -Filter '*.csv' -File -ErrorAction SilentlyContinue |
    ForEach-Object { $before[$_.FullName] = $true }
$startTime = Get-Date

Write-Host "Opening Requested Items export in Chrome ($Mode)..."
Start-Process -FilePath $chrome -ArgumentList $exportUrl

Write-Host 'Waiting for the download to complete...'
$timeoutSeconds = 600
$newFile = $null

while (((Get-Date) - $startTime).TotalSeconds -lt $timeoutSeconds) {
    Start-Sleep -Seconds 2

    $inProgress = Get-ChildItem -Path $downloadsFolder -Filter '*.crdownload' -File -ErrorAction SilentlyContinue
    if ($inProgress) { continue }

    $candidate = Get-ChildItem -Path $downloadsFolder -Filter '*.csv' -File -ErrorAction SilentlyContinue |
        Where-Object { -not $before.ContainsKey($_.FullName) -and $_.LastWriteTime -ge $startTime } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($candidate) {
        $size1 = $candidate.Length
        Start-Sleep -Seconds 1
        $size2 = (Get-Item $candidate.FullName).Length
        if ($size1 -eq $size2) {
            $newFile = $candidate
            break
        }
    }
}

if (-not $newFile) {
    Write-Warning "No new CSV detected in '$downloadsFolder' within $timeoutSeconds seconds."
    Write-Warning 'If the download is still running, move the file into the Data folder manually and run process_servicenow_data.py.'
    return
}

$destination = Join-Path $DownloadDir 'sc_req_item.csv'
Move-Item -Path $newFile.FullName -Destination $destination -Force
Write-Host "Staging CSV saved to $destination"

if ($SkipProcess) {
    Write-Host 'SkipProcess set; not running Delta/Parquet upsert.'
    return
}

$processor = Join-Path $repoRoot 'scripts\process_servicenow_data.py'
if (-not (Test-Path $processor)) {
    throw "Processor not found: $processor"
}

& $PythonExe $processor --mode daily --table sc_req_item --data-dir $DownloadDir
if ($LASTEXITCODE -ne 0) {
    throw "process_servicenow_data.py failed with exit code $LASTEXITCODE"
}

Write-Host 'Requested Items extract processed into Delta Lake and Parquet snapshot.'
