param(
    [int]$Seconds = 150,
    [string]$Port = 'COM4'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$bitfile = Join-Path $repo 'vivado\build\mic_dma_i2s_pcmfix_20260904c\mic_dma.runs\impl_1\mic_dma_system_wrapper.bit'
$init = Join-Path $repo 'sw\build\sdk_workspace_i2s_pcmfix_20260904c_smoke\mic_dma_hw\ps7_init.tcl'
$elf = Join-Path $repo 'sw\build\sdk_workspace_i2s_pcmfix_20260904c_smoke\mic_dma_app\Debug\mic_dma_app.elf'
foreach ($path in @($bitfile, $init, $elf)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing final physical artifact: $path" }
}
$adapter = Get-NetAdapter | Where-Object { $_.ifIndex -eq 17 }
if (-not $adapter -or $adapter.Status -ne 'Up' -or $adapter.LinkSpeed -notmatch '100') {
    throw 'InterfaceIndex 17 must be Up at 100 Mbps before acoustic acceptance'
}
$ip = Get-NetIPAddress -InterfaceIndex 17 -AddressFamily IPv4
if (-not ($ip.IPAddress -contains '192.168.1.2' -and $ip.PrefixLength -contains 24)) {
    throw 'InterfaceIndex 17 must be 192.168.1.2/24'
}
if (Get-NetUDPEndpoint -LocalPort 45123 -ErrorAction SilentlyContinue) {
    throw 'UDP 45123 is already in use'
}
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$evidence = Join-Path $repo "evidence\physical\morning_acoustic\$stamp"
New-Item -ItemType Directory -Force -Path $evidence | Out-Null
@($bitfile, $init, $elf) | ForEach-Object {
    [pscustomobject]@{ path = [IO.Path]::GetFullPath($_); sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $_).Hash }
} | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $evidence 'artifact_hashes.json')
Write-Output "MIC_MORNING_ARTIFACTS_READY evidence=$evidence"
Write-Output 'MIC_MORNING_INSTRUCTION quiet5s_left_1kHz5s_quiet5s_right_1kHz5s_quiet5s'
$acceptanceArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',
    (Join-Path $repo 'scripts\run_acoustic_acceptance.ps1'),
    '-Bitfile',$bitfile,'-InitTcl',$init,'-Elf',$elf,'-Port',$Port,
    '-Seconds',$Seconds,'-EvidenceDir',$evidence)
& powershell.exe @acceptanceArgs
exit $LASTEXITCODE
