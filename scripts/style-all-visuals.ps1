$ErrorActionPreference = 'Stop'
$pagesRoot = 'C:\Users\pebren\Development\ServiceNow-KPI\ServiceNowMetrics.Report\definition\pages'
$containerStyle = @'
      "background": [
        {
          "properties": {
            "show": {
              "expr": {
                "Literal": {
                  "Value": "true"
                }
              }
            },
            "color": {
              "solid": {
                "color": {
                  "expr": {
                    "Literal": {
                      "Value": "'#FFFFFF'"
                    }
                  }
                }
              }
            },
            "transparency": {
              "expr": {
                "Literal": {
                  "Value": "0D"
                }
              }
            }
          }
        }
      ],
      "dropShadow": [
        {
          "properties": {
            "show": {
              "expr": {
                "Literal": {
                  "Value": "true"
                }
              }
            }
          }
        }
      ],
'@

Get-ChildItem $pagesRoot -Recurse -Filter 'visual.json' | Where-Object {
  $n = $_.Directory.Name
  $n -notin @('navPanelBackground','navPanelTitle','pageNavigationPanel','titleTextbox','dashboardFrame') -and
  $n -notlike 'section*Title' -and
  $n -notlike '*Target'
} | ForEach-Object {
  $c = [IO.File]::ReadAllText($_.FullName)
  if ($c -match '"dropShadow"\s*:') { return }
  if ($c -match '(?m)^      "padding": \[') {
    $c = $c -replace '(?m)^      "padding": \[', ($containerStyle + '      "padding": [')
  }
  elseif ($c -match '(?m)^      "border": \[') {
    $c = $c -replace '(?m)^      "border": \[', ($containerStyle + '      "border": [')
  }
  elseif ($c -match '(?m)^    \}\s*$') {
    return
  }
  else {
    return
  }
  [IO.File]::WriteAllText($_.FullName, $c)
  $null = $c | ConvertFrom-Json
  Write-Output $_.FullName
}
