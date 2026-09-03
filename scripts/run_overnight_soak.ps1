param(
    [Parameter(Mandatory=$true)][string]$Bitfile,
    [Parameter(Mandatory=$true)][string]$InitTcl,
    [Parameter(Mandatory=$true)][string]$Elf,
    [Parameter(Mandatory=$true)][double]$DurationSeconds,
    [Parameter(Mandatory=$true)][string]$EvidenceDir,
    [int]$ExpectedPcmPackets = 0,
    [string]$Port = 'COM4'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$python = (Get-Command python.exe).Source
$xsct = 'E:\vivado\SDK\2019.1\bin\xsct.bat'
$adapter = Get-NetAdapter | Where-Object { $_.ifIndex -eq 17 }
if (-not $adapter) { throw 'InterfaceIndex 17 was not found' }
foreach ($path in @($Bitfile, $InitTcl, $Elf, $xsct)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing physical artifact: $path" }
}
if ($DurationSeconds -le 0) { throw 'DurationSeconds must be positive' }
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null

$manifest = [ordered]@{
    started = (Get-Date).ToString('o')
    duration_seconds = $DurationSeconds
    bitstream = [IO.Path]::GetFullPath($Bitfile)
    hdf_init_tcl = [IO.Path]::GetFullPath($InitTcl)
    elf = [IO.Path]::GetFullPath($Elf)
    source_mode = 1
    adapter = ($adapter | Select-Object Name,Status,LinkSpeed,MacAddress,ifIndex)
    ip = (Get-NetIPAddress -InterfaceIndex 17 -AddressFamily IPv4 | Select-Object IPAddress,PrefixLength,AddressState)
}
foreach ($key in @('bitstream','hdf_init_tcl','elf')) {
    $manifest["${key}_sha256"] = (Get-FileHash -Algorithm SHA256 -LiteralPath $manifest[$key]).Hash
}
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $EvidenceDir 'artifact_manifest.json') -Encoding UTF8
(Get-NetAdapterStatistics -Name $adapter.Name | ConvertTo-Json -Depth 4) | Set-Content (Join-Path $EvidenceDir 'adapter_before.json') -Encoding UTF8
(arp -a 192.168.1.10) | Set-Content (Join-Path $EvidenceDir 'arp_before.txt') -Encoding UTF8

$captureDir = Join-Path $EvidenceDir 'udp'
$pyOut = Join-Path $EvidenceDir 'python_console.log'
$pyErr = Join-Path $EvidenceDir 'python_console.err'
$uartLog = Join-Path $EvidenceDir 'uart.log'
$xsctLog = Join-Path $EvidenceDir 'xsct.log'
$pySeconds = [int][Math]::Ceiling($DurationSeconds + 10)
$uartSeconds = [int][Math]::Ceiling($DurationSeconds + 25)
$pyArgs = @(
    (Join-Path $repo 'scripts\udp_soak_receiver.py'), '--bind','0.0.0.0','--port','45123',
    '--seconds',([string]$pySeconds),'--output',$captureDir
)
if ($ExpectedPcmPackets -gt 0) { $pyArgs += @('--expected-pcm-packets',([string]$ExpectedPcmPackets)) }
$py = Start-Process -FilePath $python -ArgumentList $pyArgs -RedirectStandardOutput $pyOut -RedirectStandardError $pyErr -PassThru -WindowStyle Hidden
$uart = $null
$xsctExit = 1
try {
    Start-Sleep -Milliseconds 750
    $uart = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $repo 'scripts\capture_uart.ps1'),
        '-Port',$Port,'-Seconds',$uartSeconds,'-Output',$uartLog
    ) -RedirectStandardOutput (Join-Path $EvidenceDir 'uart_capture_console.log') -RedirectStandardError (Join-Path $EvidenceDir 'uart_capture_console.err') -PassThru -WindowStyle Hidden
    $env:MIC_BITFILE = [IO.Path]::GetFullPath($Bitfile)
    $env:MIC_INIT_TCL = [IO.Path]::GetFullPath($InitTcl)
    $env:MIC_ELF = [IO.Path]::GetFullPath($Elf)
    Remove-Item Env:MIC_OBSERVE_ONLY -ErrorAction SilentlyContinue
    & $xsct (Join-Path $repo 'scripts\program_physical_mic.xsct') 2>&1 | Tee-Object -FilePath $xsctLog
    $xsctExit = $LASTEXITCODE
} finally {
    if ($uart) {
        try { Wait-Process -Id $uart.Id -Timeout ($uartSeconds + 5) -ErrorAction SilentlyContinue } catch {}
        if (-not $uart.HasExited) { Stop-Process -Id $uart.Id -Force -ErrorAction SilentlyContinue }
    }
    try { Wait-Process -Id $py.Id -Timeout 20 -ErrorAction SilentlyContinue } catch {}
    if (-not $py.HasExited) { Stop-Process -Id $py.Id -Force -ErrorAction SilentlyContinue }
}
(Get-NetAdapterStatistics -Name $adapter.Name | ConvertTo-Json -Depth 4) | Set-Content (Join-Path $EvidenceDir 'adapter_after.json') -Encoding UTF8
(arp -a 192.168.1.10) | Set-Content (Join-Path $EvidenceDir 'arp_after.txt') -Encoding UTF8
$manifest.finished = (Get-Date).ToString('o')
$manifest.xsct_exit = $xsctExit
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $EvidenceDir 'artifact_manifest.json') -Encoding UTF8
if ($xsctExit -ne 0) { exit $xsctExit }
Write-Output "MIC_OVERNIGHT_SOAK_COMPLETE evidence=$EvidenceDir"
