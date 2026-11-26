$ErrorActionPreference = 'Stop'
$pagesRoot = 'C:\Users\pebren\Development\ServiceNow-KPI\ServiceNowMetrics.Report\definition\pages'

function Update-PageTitleVisual {
  param([string]$Path)

  $json = Get-Content $Path -Raw | ConvertFrom-Json
  $titleText = $json.visual.objects.general[0].properties.paragraphs[0].textRuns[0].value

  $json.position.x = 0
  $json.position.y = 0
  $json.position.width = 1280
  $json.position.height = 56

  $json.visual.objects.general[0].properties.paragraphs[0].textRuns[0].textStyle = [ordered]@{
    fontFamily = 'Segoe UI Semibold'
    fontSize   = '18pt'
    color      = '#FFFFFF'
  }
  $json.visual.objects.general[0].properties.paragraphs[0].horizontalTextAlignment = 'left'

  $json.visual.visualContainerObjects.background = @(
    [ordered]@{
      properties = [ordered]@{
        show         = @{ expr = @{ Literal = @{ Value = 'true' } } }
        color        = @{ solid = @{ color = @{ expr = @{ Literal = @{ Value = "'#01193F'" } } } } } }
        transparency = @{ expr = @{ Literal = @{ Value = '0D' } } }
      }
    }
  )
  $json.visual.visualContainerObjects.border = @(
    [ordered]@{ properties = @{ show = @{ expr = @{ Literal = @{ Value = 'false' } } } } }
  )
  $json.visual.visualContainerObjects.padding = @(
    [ordered]@{
      properties = [ordered]@{
        left = @{ expr = @{ Literal = @{ Value = '24D' } } }
        top  = @{ expr = @{ Literal = @{ Value = '12D' } } }
      }
    }
  )

  ($json | ConvertTo-Json -Depth 100) | Set-Content $Path -Encoding UTF8
  Write-Output "Title: $titleText"
}

function Update-SectionTitleVisual {
  param([string]$Path)

  $json = Get-Content $Path -Raw | ConvertFrom-Json
  $json.visual.objects.general[0].properties.paragraphs[0].textRuns[0].textStyle.fontFamily = 'Segoe UI Semibold'
  $json.visual.objects.general[0].properties.paragraphs[0].textRuns[0].textStyle.fontSize = '12pt'
  $json.visual.objects.general[0].properties.paragraphs[0].textRuns[0].textStyle.color = '#FFFFFF'
  $json.visual.objects.general[0].properties.paragraphs[0].horizontalTextAlignment = 'center'

  $json.visual.visualContainerObjects.background = @(
    [ordered]@{
      properties = [ordered]@{
        show         = @{ expr = @{ Literal = @{ Value = 'true' } } }
        color        = @{ solid = @{ color = @{ expr = @{ Literal = @{ Value = "'#01193F'" } } } } } }
        transparency = @{ expr = @{ Literal = @{ Value = '0D' } } }
      }
    }
  )

  ($json | ConvertTo-Json -Depth 100) | Set-Content $Path -Encoding UTF8
  Write-Output "Section: $($json.name)"
}

Get-ChildItem $pagesRoot -Recurse -Filter 'visual.json' | Where-Object {
  $_.Directory.Name -eq 'titleTextbox' -and $_.Directory.Parent.Parent.Name -ne 'd5084125a0d50d829885'
} | ForEach-Object { Update-PageTitleVisual $_.FullName }

Get-ChildItem "$pagesRoot\employeeProductivityPage\visuals\section*Title\visual.json" | ForEach-Object {
  Update-SectionTitleVisual $_.FullName
}
