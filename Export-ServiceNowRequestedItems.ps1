<#
.SYNOPSIS
    Extracts Requested Items (sc_req_item) from ServiceNow to CSV by opening the
    export URL in Google Chrome.

.DESCRIPTION
    Builds a ServiceNow list-export URL for the Requested Items (sc_req_item)
    table using the SAME column set as Export-ServiceNowIncidents.ps1, filtered
    by assignment group and opened date (last 24 calendar months from the first
    day of the current month, computed at run time). No state/active filter so
    every requested item in that window is included regardless of status.
    then opens it in Google Chrome. The export endpoint returns 401 if Chrome has
    no active ServiceNow session (it does not redirect to SSO), so the script
    first opens the Service Portal to let you sign in, waits for confirmation,
    then opens the export URL. Chrome downloads to your default Downloads folder
    using the signed-in session; the script then waits for that download to
    finish and moves the resulting CSV into the folder given by -DownloadDir
    (default C:\Users\pebren\Development\ServiceNow-KPI\Data).

    Note: sc_req_item and incident both extend the task table, so the shared
    task columns (number, opened_at, assignment_group, assigned_to, dates, etc.)
    resolve on both tables. Incident-only fields that do not exist on
    sc_req_item are simply returned empty by ServiceNow so the column layout
    still matches the incident export.

.PARAMETER InstanceUrl
    Base URL of the ServiceNow instance.

.PARAMETER AssignmentGroup
    Display name of the assignment group to filter on.

.EXAMPLE
    .\Export-ServiceNowRequestedItems.ps1
#>
[CmdletBinding()]
param(
    [string]$InstanceUrl = 'https://assaabloy.service-now.com',

    [string]$AssignmentGroup = 'AAES - North America - User IT Workplace',

    # Folder the downloaded CSV is moved into once Chrome finishes downloading.
    [string]$DownloadDir = 'C:\Users\pebren\Development\ServiceNow-KPI\Data'
)

$ErrorActionPreference = 'Stop'

# Exact column order for the extract (mirrors Export-ServiceNowIncidents.ps1)
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

# Last 24 months: from the first day of the calendar month that is 24 months
# before the current month through today (computed when the script runs).
$currentMonthStart = Get-Date -Year (Get-Date).Year -Month (Get-Date).Month -Day 1 -Hour 0 -Minute 0 -Second 0
$openedOnOrAfter = $currentMonthStart.AddMonths(-24)
$openedOnOrAfterStr = $openedOnOrAfter.ToString('yyyy-MM-dd HH:mm:ss')

$query = [uri]::EscapeDataString(
    "assignment_group.name=$AssignmentGroup^opened_at>=$openedOnOrAfterStr^ORDERBYnumber"
)

# Requested Items are stored in the sc_req_item table.
$exportUrl = "$instance/sc_req_item_list.do?CSV&sysparm_query=$query&sysparm_fields=$($fields -join ',')"

# Locate chrome.exe (standard install locations, then PATH)
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

# Step 1: open the Service Portal so Chrome establishes a ServiceNow session.
# The CSV export endpoint returns 401 when no session exists, so this must
# happen before the export URL is opened.
Write-Host 'Opening ServiceNow in Chrome so you can sign in (skip if already signed in)...'
Start-Process -FilePath $chrome -ArgumentList "$instance/sp"

Read-Host 'Once the ServiceNow portal has loaded and you are signed in, press Enter to start the export'

# Ensure the destination folder exists.
if (-not (Test-Path $DownloadDir)) {
    New-Item -ItemType Directory -Path $DownloadDir -Force | Out-Null
}

# Resolve the browser's default Downloads folder so we can detect the new file.
$downloadsFolder = Join-Path $env:USERPROFILE 'Downloads'

# Record CSV files already present so we can identify the freshly downloaded one.
$before = @{}
Get-ChildItem -Path $downloadsFolder -Filter '*.csv' -File -ErrorAction SilentlyContinue |
    ForEach-Object { $before[$_.FullName] = $true }
$startTime = Get-Date

# Step 2: open the export URL; the CSV downloads using the session just created.
Write-Host "Opening Requested Items export in Chrome for assignment group '$AssignmentGroup'..."
Write-Host "Date filter: opened_at >= $openedOnOrAfterStr (24 months from current month start)"
Start-Process -FilePath $chrome -ArgumentList $exportUrl

# Step 3: wait for Chrome to finish downloading, then move the file.
Write-Host 'Waiting for the download to complete...'
$timeoutSeconds = 600
$newFile = $null

while (((Get-Date) - $startTime).TotalSeconds -lt $timeoutSeconds) {
    Start-Sleep -Seconds 2

    # A download in progress shows up as a .crdownload file in Chrome.
    $inProgress = Get-ChildItem -Path $downloadsFolder -Filter '*.crdownload' -File -ErrorAction SilentlyContinue
    if ($inProgress) { continue }

    $candidate = Get-ChildItem -Path $downloadsFolder -Filter '*.csv' -File -ErrorAction SilentlyContinue |
        Where-Object { -not $before.ContainsKey($_.FullName) -and $_.LastWriteTime -ge $startTime } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($candidate) {
        # Confirm the file size is stable before moving it.
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
    Write-Warning 'If the download is still running, move the file into the Data folder manually.'
    return
}

$destination = Join-Path $DownloadDir $newFile.Name
Move-Item -Path $newFile.FullName -Destination $destination -Force

Write-Host "Done. CSV saved to $destination"
