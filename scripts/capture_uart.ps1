param(
    [string]$Port = "COM4",
    [int]$Seconds = 8,
    [int]$Baud = 115200,
    [string]$Output = "",
    [string]$StopFile = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($Output)) {
    $Output = Join-Path (Join-Path $PSScriptRoot "..\evidence\physical") ("uart_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
}
$parent = Split-Path -Parent ([IO.Path]::GetFullPath($Output))
New-Item -ItemType Directory -Force -Path $parent | Out-Null
$serial = [System.IO.Ports.SerialPort]::new($Port, $Baud, [IO.Ports.Parity]::None, 8, [IO.Ports.StopBits]::One)
$serial.ReadTimeout = 100
$serial.Open()
$deadline = (Get-Date).AddSeconds($Seconds)
$builder = [Text.StringBuilder]::new()
$writer = [IO.StreamWriter]::new($Output, $false, [Text.UTF8Encoding]::new($false))
$writer.AutoFlush = $true
try {
    while ((Get-Date) -lt $deadline) {
        if (-not [string]::IsNullOrWhiteSpace($StopFile) -and (Test-Path -LiteralPath $StopFile)) { break }
        try {
            $chunk = $serial.ReadExisting()
            if ($chunk.Length -gt 0) {
                [void]$builder.Append($chunk)
                $writer.Write($chunk)
            }
        } catch [TimeoutException] {}
        Start-Sleep -Milliseconds 50
    }
} finally {
    $serial.Close()
    $writer.Dispose()
}
$captured = $builder.ToString()
Write-Output ("MIC_UART_CAPTURE path={0} bytes={1}" -f $Output, $builder.Length)
if ($builder.Length -gt 0) { $captured }
