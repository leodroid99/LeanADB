$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $projectRoot 'LeanADB.ps1'
$missingRoot = Join-Path ([IO.Path]::GetTempPath()) ('LeanADB-language-test-' + [guid]::NewGuid().ToString('N'))
$originalUiCulture = [Threading.Thread]::CurrentThread.CurrentUICulture
$originalCulture = [Threading.Thread]::CurrentThread.CurrentCulture

function Assert-Contains {
    param([string]$Text, [string]$Expected, [string]$CaseName)
    if (-not $Text.Contains($Expected)) {
        throw "$CaseName failed. Output: $Text"
    }
}

try {
    [Threading.Thread]::CurrentThread.CurrentUICulture = [Globalization.CultureInfo]'en-US'
    [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]'ko-KR'
    $automaticEnglish = (& $scriptPath -Action Status -InstallPath $missingRoot *>&1 | Out-String)
    Assert-Contains -Text $automaticEnglish -Expected 'LeanADB is not installed at' -CaseName 'English UI with Korean regional format'

    [Threading.Thread]::CurrentThread.CurrentUICulture = [Globalization.CultureInfo]'ko-KR'
    $forcedEnglish = (& $scriptPath -Action Status -InstallPath $missingRoot -Language English *>&1 | Out-String)
    Assert-Contains -Text $forcedEnglish -Expected 'LeanADB is not installed at' -CaseName 'English override'

    [Threading.Thread]::CurrentThread.CurrentUICulture = [Globalization.CultureInfo]'en-US'
    $forcedKorean = (& $scriptPath -Action Status -InstallPath $missingRoot -Language Korean *>&1 | Out-String)
    $koreanWord = -join @([char]0xC124, [char]0xCE58)
    Assert-Contains -Text $forcedKorean -Expected $koreanWord -CaseName 'Korean override'

    $source = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8
    $messageBlock = [regex]::Match($source, '\$script:Messages\s*=\s*@\{(?<body>[\s\S]*?)\r?\n\}')
    if (-not $messageBlock.Success) { throw 'Could not find English message table.' }
    $englishKeys = @([regex]::Matches($messageBlock.Groups['body'].Value, '(?m)^\s*([A-Za-z][A-Za-z0-9]*)\s*=') | ForEach-Object { $_.Groups[1].Value })
    $koreanKeys = @((Get-Content -LiteralPath (Join-Path $projectRoot 'locales\ko.json') -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties.Name)
    $missingKeys = @($englishKeys | Where-Object { $_ -notin $koreanKeys })
    $extraKeys = @($koreanKeys | Where-Object { $_ -notin $englishKeys })
    if ($missingKeys.Count -or $extraKeys.Count) {
        throw "Localization keys differ. Missing Korean: $($missingKeys -join ', '); extra Korean: $($extraKeys -join ', ')"
    }
    Write-Host "LeanADB language test passed ($($englishKeys.Count) messages)."
}
finally {
    [Threading.Thread]::CurrentThread.CurrentUICulture = $originalUiCulture
    [Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture
}
