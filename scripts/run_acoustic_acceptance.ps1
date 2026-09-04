param(
    [string]$Bitfile = "D:\microphone\vivado\build\mic_dma_i2s_pcmfix_20260904c\mic_dma.runs\impl_1\mic_dma_system_wrapper.bit",
    [string]$InitTcl = "D:\microphone\sw\build\sdk_workspace_i2s_pcmfix_20260904c_smoke\mic_dma_hw\ps7_init.tcl",
    [string]$Elf = "D:\microphone\sw\build\sdk_workspace_i2s_pcmfix_20260904c_smoke\mic_dma_app\Debug\mic_dma_app.elf",
    [string]$Port = "COM4",
    [int]$Seconds = 150,
    [string]$EvidenceDir = "D:\microphone\evidence\physical\morning_acoustic"
)
$ErrorActionPreference = "Stop"
$repo = "D:\microphone"
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
Remove-Item -LiteralPath (Join-Path $EvidenceDir "matlab_ready.flag"), (Join-Path $EvidenceDir "live_capture.mat") -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $EvidenceDir "analysis") -Recurse -Force -ErrorAction SilentlyContinue
function Save-AdapterStats([string]$Path) {
    $adapter = Get-NetAdapter | Where-Object { $_.ifIndex -eq 17 }
    if (-not $adapter) { throw "InterfaceIndex 17 not found" }
    try { Get-NetAdapterStatistics -Name $adapter.Name | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $Path }
    catch { $adapter | Select-Object Name,MacAddress,Status,LinkSpeed,ifIndex | ConvertTo-Json | Set-Content -Encoding UTF8 $Path }
}
$adapter = Get-NetAdapter | Where-Object { $_.ifIndex -eq 17 } | Select-Object Name,MacAddress,Status,LinkSpeed,ifIndex
if (-not $adapter) { throw "InterfaceIndex 17 not found" }
$adapter | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $EvidenceDir "adapter.json")
Save-AdapterStats (Join-Path $EvidenceDir "adapter_before.json")
$endpoint = Get-NetUDPEndpoint -LocalPort 45123 -ErrorAction SilentlyContinue
if ($endpoint) { throw "UDP 45123 is already in use: $($endpoint | Out-String)" }
$ruleName = "MIC acoustic UDP 45123 temporary"
try {
    if (-not (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow -Protocol UDP -LocalPort 45123 -InterfaceAlias $adapter.Name -Profile Any -ErrorAction Stop | Out-Null
    }
    "MIC_FIREWALL_RULE_READY $ruleName" | Set-Content -Encoding UTF8 (Join-Path $EvidenceDir "firewall.txt")
} catch {
    "MIC_FIREWALL_RULE_ADMIN_REQUIRED" | Set-Content -Encoding UTF8 (Join-Path $EvidenceDir "firewall.txt")
    "New-NetFirewallRule -DisplayName '$ruleName' -Direction Inbound -Action Allow -Protocol UDP -LocalPort 45123 -InterfaceAlias '$($adapter.Name)' -Profile Any" | Set-Content -Encoding UTF8 (Join-Path $EvidenceDir "firewall_admin_command.txt")
}
foreach ($path in @($Bitfile,$InitTcl,$Elf)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing artifact: $path" }
}
$python = "D:\python3.12.3\python.exe"
if (-not (Test-Path $python)) { $python = (Get-Command python.exe).Source }
$matlab = "C:\Program Files\MATLAB\R2024a\bin\matlab.exe"
if (-not (Test-Path $matlab)) { throw "MATLAB R2024a not found: $matlab" }
$matlabOut = Join-Path $EvidenceDir "matlab_console.log"
$matlabSave = Join-Path $EvidenceDir "live_capture.mat"
$ready = Join-Path $EvidenceDir "matlab_ready.flag"
$matlabSeconds = $Seconds + 45
$matlabExpr = "cd('$repo');addpath('$repo\matlab');run_live_capture_once('$matlabSave',$matlabSeconds,true,'$ready');exit"
$matlabProc = Start-Process -FilePath $matlab -ArgumentList @("-desktop","-logfile",$matlabOut,"-r",$matlabExpr) -PassThru
$bindDeadline = (Get-Date).AddSeconds(30)
while (-not (Get-NetUDPEndpoint -LocalPort 45123 -ErrorAction SilentlyContinue) -and (Get-Date) -lt $bindDeadline) { Start-Sleep -Seconds 1 }
$uartOut = Join-Path $EvidenceDir "uart.log"
$uartProc = Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File","$repo\scripts\capture_uart.ps1","-Port",$Port,"-Seconds",$matlabSeconds,"-Output",$uartOut) -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 8
$env:MIC_BITFILE = [IO.Path]::GetFullPath($Bitfile)
$env:MIC_INIT_TCL = [IO.Path]::GetFullPath($InitTcl)
$env:MIC_ELF = [IO.Path]::GetFullPath($Elf)
Remove-Item Env:MIC_OBSERVE_ONLY -ErrorAction SilentlyContinue
$xsctLog = Join-Path $EvidenceDir "xsct.log"
& "E:\vivado\SDK\2019.1\bin\xsct.bat" "$repo\scripts\program_physical_mic.xsct" 2>&1 | Tee-Object -FilePath $xsctLog
$xsctExit = $LASTEXITCODE
$readyDeadline = (Get-Date).AddSeconds(45)
while (-not (Test-Path $ready) -and (Get-Date) -lt $readyDeadline) {
    Start-Sleep -Seconds 1
}
if (Test-Path $ready) {
    Write-Output "MIC_ACOUSTIC_ACTION_READY"
    Write-Output "MIC_ACOUSTIC_ACTION_INSTRUCTION quiet3s_clap3x_1s_gap_quiet3s"
} else {
    Write-Output "MIC_ACOUSTIC_ACTION_READY_TIMEOUT"
}
$endDeadline = (Get-Date).AddSeconds([Math]::Max(20, $Seconds))
while ((Get-Date) -lt $endDeadline) { Start-Sleep -Seconds 1 }
foreach ($proc in @($uartProc,$matlabProc)) {
    try { Wait-Process -Id $proc.Id -Timeout 45 -ErrorAction SilentlyContinue } catch {}
}
$pythonOut = Join-Path $EvidenceDir "python_mat_analysis.out"
$pythonErr = Join-Path $EvidenceDir "python_mat_analysis.err"
& $python "${repo}\scripts\analyze_live_mat.py" $matlabSave "--output" (Join-Path $EvidenceDir "analysis") 1> $pythonOut 2> $pythonErr
$detectOut = Join-Path $EvidenceDir "acoustic_response.out"
$detectErr = Join-Path $EvidenceDir "acoustic_response.err"
& $python "${repo}\scripts\detect_acoustic_response.py" $matlabSave "--output" (Join-Path $EvidenceDir "acoustic_response") 1> $detectOut 2> $detectErr
Save-AdapterStats (Join-Path $EvidenceDir "adapter_after.json")
if ($xsctExit -ne 0) { exit $xsctExit }
