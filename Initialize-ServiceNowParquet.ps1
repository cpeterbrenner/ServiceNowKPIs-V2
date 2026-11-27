<#
.SYNOPSIS
    One-time / rebuild initial load: CSV files in Data/ -> Delta Lake + Parquet.

.DESCRIPTION
    Reads existing Data\incident.csv and Data\sc_req_item.csv, filters out
    Guest Guest, writes Delta tables under Data\delta\, and publishes
    Data\incident.parquet and Data\sc_req_item.parquet for Power BI.

.EXAMPLE
    .\Initialize-ServiceNowParquet.ps1
#>
[CmdletBinding()]
param(
    [string]$DataDir = 'C:\Users\pebren\Development\ServiceNow-KPI-V2\Data',
    [string]$PythonExe = 'python'
)

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot
$processor = Join-Path $repoRoot 'scripts\process_servicenow_data.py'

if (-not (Test-Path $processor)) {
    throw "Processor not found: $processor"
}

Write-Host "Running initial Parquet/Delta load from $DataDir ..."
& $PythonExe $processor --mode initial --table all --data-dir $DataDir
if ($LASTEXITCODE -ne 0) {
    throw "process_servicenow_data.py failed with exit code $LASTEXITCODE"
}

Write-Host 'Initial load complete.'
