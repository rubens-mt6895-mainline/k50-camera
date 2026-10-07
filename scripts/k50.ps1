# k50.ps1 - talk to the Redmi K50 running Debian, over its USB gadget serial
#           (g_serial / ttyGS0, discovered as "USB Serial Device", VID_0525&PID_A4A7).
#
#   .\k50.ps1                          interactive terminal (type commands, see output)
#   .\k50.ps1 -Cmd "uname -a"          run one command, print its output, exit
#   .\k50.ps1 -Push .\fastfetch -Remote /usr/local/bin
#                                      copy a local file to the phone (base64 over
#                                      the tty + md5 check), then chmod +x
#   .\k50.ps1 -Port COM9               skip auto-detection
#
# Quit the interactive terminal with Ctrl+C.  A COM port can only be open by one
# program at a time - close PuTTY / the Arduino monitor first.

[CmdletBinding()]
param(
    [string]$Cmd,
    [string]$Port,
    [int]$Baud = 115200,
    [int]$TimeoutMs = 2500,
    [string]$Push,                       # local file to send
    [string]$Remote = '/root',           # destination directory on the phone
    [switch]$NoExec                      # do not chmod +x the pushed file
)

$ErrorActionPreference = 'Stop'

function Find-K50Port {
    # The gadget identifies itself as VID_0525 PID_A4A7 (Linux gadget serial),
    # so we do not have to guess which COM number it got this time.
    $dev = Get-PnpDevice -Class Ports -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -eq 'OK' -and $_.InstanceId -like '*VID_0525*PID_A4A7*' } |
        Select-Object -First 1
    if ($dev -and $dev.FriendlyName -match '\((COM\d+)\)') { return $Matches[1] }

    # fall back: any OK port whose name mentions serial / USB
    $dev = Get-PnpDevice -Class Ports -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -eq 'OK' -and $_.FriendlyName -match 'COM\d+' -and
                       $_.FriendlyName -notmatch 'LPT|Printer|Communications Port' } |
        Select-Object -First 1
    if ($dev -and $dev.FriendlyName -match '\((COM\d+)\)') { return $Matches[1] }
    return $null
}

if (-not $Port) {
    $Port = Find-K50Port
    if (-not $Port) {
        Write-Host 'K50 not found.' -ForegroundColor Red
        Write-Host 'Check: phone plugged in, booted into Debian (not Android/fastboot), and no'
        Write-Host 'other program holding the port.  Or pass -Port COMx explicitly.'
        exit 1
    }
}

$sp = New-Object System.IO.Ports.SerialPort $Port, $Baud, 'None', 8, 'One'
$sp.ReadTimeout = $TimeoutMs
$sp.WriteTimeout = 5000
$sp.DtrEnable = $false
$sp.RtsEnable = $false

try { $sp.Open() } catch {
    Write-Host "Cannot open $Port : $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

function Read-For([int]$ms) {
    $deadline = (Get-Date).AddMilliseconds($ms)
    $sb = New-Object System.Text.StringBuilder
    while ((Get-Date) -lt $deadline) {
        try { $chunk = $sp.ReadExisting(); if ($chunk) { [void]$sb.Append($chunk) } } catch {}
        Start-Sleep -Milliseconds 40
    }
    return $sb.ToString()
}

try {
    if ($Push) {
        $path = (Resolve-Path $Push).Path
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $name = Split-Path $path -Leaf
        $dest = "$($Remote.TrimEnd('/'))/$name"
        $localMd5 = (Get-FileHash -Algorithm MD5 $path).Hash.ToLower()

        # base64 wrapped with plain LF.  LF is not remapped by the tty (INLCR is
        # off) and the base64 alphabet holds no control character, so the stream
        # passes through the canonical line discipline byte for byte.
        $b64 = [Convert]::ToBase64String($bytes)
        $sb = New-Object System.Text.StringBuilder
        for ($i = 0; $i -lt $b64.Length; $i += 76) {
            $n = [Math]::Min(76, $b64.Length - $i)
            [void]$sb.Append($b64.Substring($i, $n)).Append("`n")
        }
        $payload = [System.Text.Encoding]::ASCII.GetBytes($sb.ToString())

        Write-Host "push $name : $([math]::Round($bytes.Length/1KB,1)) KB -> $dest" -ForegroundColor Green
        Write-Host "  payload $($payload.Length) bytes, md5 $localMd5"

        $sp.ReadTimeout = 500
        # -echo: the tty would otherwise mirror 3.4 MB straight back at us.
        # head -c N: reads exactly N bytes and then exits on its own, so the end
        # of the transfer is a byte count, not the line discipline's guess at
        # "end of input" (Ctrl-D).
        $sp.Write("stty -echo`r"); Start-Sleep -Milliseconds 400
        $sp.Write("rm -f /tmp/.k50.b64`r"); Start-Sleep -Milliseconds 400
        $sp.Write("head -c $($payload.Length) > /tmp/.k50.b64`r")
        Start-Sleep -Milliseconds 800

        # hand the bytes to the USB stack and let *it* do the flow control: the
        # gadget NAKs once its tty buffer is full, so nothing can be dropped.
        # (The old 256 byte / 18 ms pacing was the ~11 KB/s ceiling.)
        $sp.WriteTimeout = 600000
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $block = 32768
        for ($i = 0; $i -lt $payload.Length; $i += $block) {
            $n = [Math]::Min($block, $payload.Length - $i)
            $sp.Write($payload, $i, $n)
            $pct = [int](100 * ($i + $n) / $payload.Length)
            Write-Host -NoNewline "`r  sending... $pct%  ($($sw.Elapsed.TotalSeconds.ToString('0.0'))s)"
        }
        Write-Host ''

        Start-Sleep -Milliseconds 600
        $sp.Write("stty echo`r"); Start-Sleep -Milliseconds 300
        $sp.Write("wc -c /tmp/.k50.b64`r"); Start-Sleep -Milliseconds 300
        $sp.Write("base64 -d /tmp/.k50.b64 > $dest && echo DECODE_OK; md5sum $dest`r")
        $out = Read-For 4000
        Write-Host $out
        if ($out -match '([0-9a-f]{32})') {
            $remoteMd5 = $Matches[1]
            if ($remoteMd5 -eq $localMd5) {
                Write-Host "md5 OK ($localMd5)" -ForegroundColor Green
                if (-not $NoExec) {
                    $sp.Write("chmod +x $dest`r"); Start-Sleep -Milliseconds 400
                    [void](Read-For 400)
                }
            } else {
                Write-Host "md5 MISMATCH: local $localMd5 remote $remoteMd5" -ForegroundColor Red
            }
        } else {
            Write-Host 'md5 not seen in the output - check the log above.' -ForegroundColor Yellow
        }
        return
    }

    if ($Cmd) {
        # one-shot: send, collect for a while, strip the echoed command line
        $sp.DiscardInBuffer()
        $sp.Write("$Cmd`r")
        $lines = (Read-For $TimeoutMs) -split "`r?`n"
        ($lines | Where-Object { $_.Trim() -ne $Cmd.Trim() }) -join "`n"
        return
    }

    Write-Host "connected to $Port at $Baud - type commands, Ctrl+C to quit" -ForegroundColor Green
    # nudge the remote getty so it redraws its prompt even if it printed it
    # before we attached (and drop anything left over from the previous session)
    Start-Sleep -Milliseconds 150
    $sp.DiscardInBuffer()
    $sp.Write("`r")
    Start-Sleep -Milliseconds 300
    $sp.Write("`r")

    while ($true) {
        # 1) print anything the phone sent
        try {
            $chunk = $sp.ReadExisting()
            if ($chunk) { Write-Host -NoNewline $chunk }
        } catch {}

        # 2) forward local key presses (the remote tty does the echoing)
        while ([Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)
            switch ($k.Key) {
                'Enter'     { $sp.Write("`r") }
                'Backspace' { $sp.Write([string][char]127) }
                'Tab'       { $sp.Write("`t") }
                default {
                    if ($k.KeyChar -and [int]$k.KeyChar -ge 32) {
                        $sp.Write([string]$k.KeyChar)
                    }
                }
            }
        }
        Start-Sleep -Milliseconds 15
    }
} finally {
    if ($sp.IsOpen) { $sp.Close() }
}
