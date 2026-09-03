param(
    [string]$VivadoBin = 'E:\vivado\Vivado\2019.1\bin',
    [string]$Repo = 'D:\microphone'
)
$ErrorActionPreference = 'Stop'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$root = Join-Path $Repo "vivado\build\rtl_cli_tests\$stamp"
New-Item -ItemType Directory -Force -Path $root | Out-Null

$tests = @(
    @{ Top = 'tb_pcm_synthetic_source'; Token = 'MIC_FRONTEND_RTL_PASS'; Sources = @('rtl\pcm_synthetic_source.sv', 'tb\tb_pcm_synthetic_source.sv') },
    @{ Top = 'tb_pcm_axis_packer'; Token = 'MIC_PACKER_RTL_PASS'; Sources = @('rtl\pcm_axis_packer.sv', 'tb\tb_pcm_axis_packer.sv') },
    @{ Top = 'tb_lc_ai_k210_7mic_frontend'; Token = 'MIC_I2S_SCALE_RTL_PASS'; Sources = @('rtl\lc_ai_k210_7mic_frontend.sv', 'tb\tb_lc_ai_k210_7mic_frontend.sv') }
)

foreach ($test in $tests) {
    $dir = Join-Path $root $test.Top
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Push-Location $dir
    try {
        $sourceArgs = @('--sv') + @($test.Sources | ForEach-Object { Join-Path $Repo $_ })
        & (Join-Path $VivadoBin 'xvlog.bat') @sourceArgs 2>&1 | Tee-Object -FilePath (Join-Path $dir 'xvlog_console.log')
        if ($LASTEXITCODE -ne 0) { throw "xvlog failed for $($test.Top)" }
        & (Join-Path $VivadoBin 'xelab.bat') '-debug' 'typical' '-top' $test.Top '-snapshot' "$($test.Top)_sim" 2>&1 | Tee-Object -FilePath (Join-Path $dir 'xelab_console.log')
        if ($LASTEXITCODE -ne 0) { throw "xelab failed for $($test.Top)" }
        $simOutput = & (Join-Path $VivadoBin 'xsim.bat') "$($test.Top)_sim" '-runall' '-log' (Join-Path $dir 'xsim.log') 2>&1
        $simOutput | Tee-Object -FilePath (Join-Path $dir 'xsim_console.log')
        if ($LASTEXITCODE -ne 0) { throw "xsim failed for $($test.Top)" }
        $combined = ($simOutput -join "`n")
        if ($combined -notmatch [regex]::Escape($test.Token)) { throw "missing $($test.Token) for $($test.Top)" }
        if ($combined -match 'Fatal:|_FAIL|\bERROR\b') { throw "failure marker for $($test.Top)" }
        Write-Output "RTL_TEST_PASS top=$($test.Top)"
    } finally {
        Pop-Location
    }
}
Write-Output 'MIC_RTL_SUITE_PASS'
