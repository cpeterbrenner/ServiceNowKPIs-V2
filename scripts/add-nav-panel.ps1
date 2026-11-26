$ErrorActionPreference = 'Stop'
$base = 'C:\Users\pebren\Development\ServiceNow-KPI\ServiceNowMetrics.Report\definition\pages'
$shared = Join-Path $base '_shared'
$navWidth = 180
$cardMap = @{24=204; 330=475; 636=746; 942=1017}
$newCardWidth = 255
$pages = @(
  'd5084125a0d50d829885',
  'activeIncidentsPage',
  'unassignedIncidentsPage',
  'openIncidentsLt30Page',
  'openIncidents3060Page',
  'openIncidentsGt60Page',
  'mttrRolling12Page'
)

foreach ($page in $pages) {
  foreach ($nav in @('navPanelBackground', 'navPanelTitle', 'pageNavigationPanel')) {
    $destDir = Join-Path $base "$page\visuals\$nav"
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    Copy-Item (Join-Path $shared "$nav.json") (Join-Path $destDir 'visual.json') -Force
  }
}

function Get-NearestCardCol([double]$x) {
  $cols = @(24, 330, 636, 942)
  $nearest = $cols[0]
  foreach ($c in $cols) {
    if ([math]::Abs($x - $c) -lt [math]::Abs($x - $nearest)) {
      $nearest = $c
    }
  }
  return $nearest
}

$count = 0
Get-ChildItem (Join-Path $base '*\visuals\*\visual.json') | ForEach-Object {
  $visName = $_.Directory.Name
  if ($visName -in @('navPanelBackground', 'navPanelTitle', 'pageNavigationPanel')) {
    return
  }

  $json = Get-Content $_.FullName -Raw | ConvertFrom-Json
  $pageName = $_.Directory.Parent.Parent.Name
  $isDashboard = $pageName -eq 'd5084125a0d50d829885'

  if ($isDashboard) {
    if ($visName -eq 'dashboardFrame') {
      $json.position.x = 190
      $json.position.width = 1080
    }
    elseif ($visName -like 'card*') {
      $oldX = [double]$json.position.x
      $oldCol = Get-NearestCardCol $oldX
      if ($cardMap.ContainsKey($oldCol)) {
        $json.position.x = [double]$cardMap[$oldCol]
        $json.position.width = [double]$newCardWidth
      }
    }
    elseif ($visName -eq 'openedDateSlicer') {
      $json.position.x = 1004
    }
    elseif ($visName -like '*NavButton' -or $visName -eq '6ed3cc219d89e287b038') {
      $oldX = [double]$json.position.x
      $oldCol = Get-NearestCardCol ($oldX - 200)
      if ($cardMap.ContainsKey($oldCol)) {
        $json.position.x = [double]$cardMap[$oldCol] + ($oldX - $oldCol)
        if ($json.position.x + [double]$json.position.width -gt 1280) {
          $json.position.x = 1280 - [double]$json.position.width
        }
      }
      else {
        $json.position.x = $oldX + $navWidth
      }
    }
    else {
      $json.position.x = [double]$json.position.x + $navWidth
    }
  }
  else {
    $json.position.x = [double]$json.position.x + $navWidth
    if ($json.position.width -and [double]$json.position.width -gt 600) {
      $json.position.width = [double]$json.position.width - $navWidth
    }
  }

  ($json | ConvertTo-Json -Depth 100) | Set-Content $_.FullName -Encoding UTF8
  $count++
}

Write-Output "Updated $count visuals across $($pages.Count) pages"
