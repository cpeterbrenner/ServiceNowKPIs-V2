$ErrorActionPreference = 'Stop'
$main = 'C:\Users\pebren\Development\ServiceNow-KPI\ServiceNowMetrics.Report\definition\pages\d5084125a0d50d829885\visuals'
$names = @(
  'cardActiveOpen', 'cardAvgAgeOpen', 'cardOldestAssignedUnresolved', 'cardOldestUnassigned',
  'cardTotalIncidents', 'cardTotalResolved', 'cardUnassigned',
  'openAgeChart', 'mttrGauge', 'mttrSlaLegend', 'openedDateSlicer'
)

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

$titleStyle = @'
            "fontSize": {
              "expr": {
                "Literal": {
                  "Value": "11D"
                }
              }
            },
            "fontColor": {
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
            "background": {
              "solid": {
                "color": {
                  "expr": {
                    "Literal": {
                      "Value": "'#01193F'"
                    }
                  }
                }
              }
            }
'@

foreach ($n in $names) {
  $path = Join-Path $main "$n\visual.json"
  if (-not (Test-Path $path)) { continue }
  $c = [IO.File]::ReadAllText($path)

  if ($c -notmatch '"dropShadow"\s*:') {
    if ($c -match '(?m)^      "padding": \[') {
      $c = $c -replace '(?m)^      "padding": \[', ($containerStyle + '      "padding": [')
    }
    elseif ($c -match '(?m)^      "border": \[') {
      $c = $c -replace '(?m)^      "border": \[', ($containerStyle + '      "border": [')
    }
  }

  if ($n -like 'card*' -and $c -match '"fontSize"') {
    $c = [regex]::Replace(
      $c,
      '(?ms)"fontSize"\s*:\s*\{\s*"expr"\s*:\s*\{\s*"Literal"\s*:\s*\{\s*"Value"\s*:\s*"12D"\s*\}\s*\}\s*\}',
      $titleStyle,
      1
    )
  }

  [IO.File]::WriteAllText($path, $c)
  $null = $c | ConvertFrom-Json
  Write-Output "Styled $n"
}
