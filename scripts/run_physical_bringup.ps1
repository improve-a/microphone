param(
    [string]$Bitfile = "",
    [string]$InitTcl = "",
    [string]$Elf = "",
    [string]$EvidenceDir = "",
    [string]$Port = "COM4",
    [int]$UartSeconds = 15
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$build = Join-Path $repo "vivado\build\mic_dma_m2reset_clean_20260902"
$sdk = Join-Path $repo "sw\build\physical_mic_clean_20260902"
if ([string]::IsNullOrWhiteSpace($Bitfile)) { $Bitfile = Join-Path $build "mic_dma.runs\impl_1\mic_dma_system_wrapper.bit" }
if ([string]::IsNullOrWhiteSpace($InitTcl)) { $InitTcl = Join-Path $sdk "mic_dma_hw\ps7_init.tcl" }
if ([string]::IsNullOrWhiteSpace($Elf)) { $Elf = Join-Path $sdk "mic_dma_app\Debug\mic_dma_app.elf" }
if ([string]::IsNullOrWhiteSpace($EvidenceDir)) { $EvidenceDir = Join-Path $repo "evidence\physical\20260903_preelf_probe" }
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null

foreach ($path in @($Bitfile, $InitTcl, $Elf)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing artifact: $path" }
}

$uartLog = Join-Path $EvidenceDir "uart.log"
$xsctLog = Join-Path $EvidenceDir "xsct.log"
$capture = Start-Process -FilePath "powershell.exe" -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "capture_uart.ps1"),
    "-Port", $Port, "-Seconds", $UartSeconds, "-Output", $uartLog
) -PassThru -WindowStyle Hidden
try {
    Start-Sleep -Milliseconds 1000
    $env:MIC_BITFILE = [IO.Path]::GetFullPath($Bitfile)
    $env:MIC_INIT_TCL = [IO.Path]::GetFullPath($InitTcl)
    $env:MIC_ELF = [IO.Path]::GetFullPath($Elf)
    $xsct = "E:\vivado\SDK\2019.1\bin\xsct.bat"
    if (-not (Test-Path -LiteralPath $xsct)) { throw "XSCT executable missing: $xsct" }
    & $xsct (Join-Path $PSScriptRoot "program_physical_mic.xsct") 2>&1 | Tee-Object -FilePath $xsctLog
    $xsctExit = $LASTEXITCODE
} finally {
    Wait-Process -Id $capture.Id -Timeout ($UartSeconds + 5) -ErrorAction SilentlyContinue
    if (-not $capture.HasExited) { Stop-Process -Id $capture.Id -Force }
}
Write-Output "MIC_PHYSICAL_BRINGUP_XSCT_LOG=$xsctLog"
Write-Output "MIC_PHYSICAL_BRINGUP_UART_LOG=$uartLog"
if ($xsctExit -ne 0) { exit $xsctExit }
