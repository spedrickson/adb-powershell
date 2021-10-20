<#
    .Synopsis
    Sends the specified file(s) to a device, using adb over wifi

    .Description
    Requires `adb` to be available in the system PATH. Install via Scoop or Chocolatey.

    .Example
    `Send-AdbFile C:\test.log`
    Sends a file to the default directory on the default adb device.
    Defaults can be set in `./adb_defaults.cfg`

    `Send-AdbFile C:\test.log /storage/emulated/0/Download`
    Sends a file to a specific directory on the default adb device 

    `Get-ChildItem *.mp3 | Send-AdbFile -d /storage/emulated/0/Music`
    Send all mp3 files in the current directory to your phone's music directory
#>
$cfgFile = Join-Path -Path $PSScriptRoot -ChildPath "adb_defaults.cfg"
function Send-AdbFile {
    [CmdletBinding(SupportsShouldProcess)]
    [alias("saf")]
    param(
        # The source file(s) that should be written to the adb device
        [Object[]][Parameter(Mandatory, ValueFromPipeline, Position=0)]
        $Source,

        # The directory on the adb device where source file(s) should be written
        #   e.g. /storage/emulated/0/Download
        [String][Parameter(Position=1)]
        $Destination = (Get-Cfg Destination),

        # The IP address of the adb device that should be written to
        [IPAddress]
        $IPAddress = (Get-Cfg IPAddress),

        # The port of the adb device that should be written to
        [Int][ValidateRange("Positive")]
        $Port = (Get-Cfg Port),

        # Disable the summary of items (successful/failed count, exec time) after processing is finished
        [Switch]
        $NoSummary
    )

    begin {
        $startTime = [System.Diagnostics.Stopwatch]::StartNew()
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $successful = 0
        $failed = 0
        $processed = 0
        $skipped = 0
        Write-Verbose "IP:           $IPAddress"
        Write-Verbose "Port:         $Port"
        Write-Verbose "destination:  $destination"
        
        # ensure `adb` is available as a command
        if (-not (Get-Command "adb" -ErrorAction SilentlyContinue)) {
            Write-Error "adb not available in PATH, see README for install instructions"; break
        }

        # ensure proper device connection before running
        if (-not (Confirm-AdbDeviceConnected -IP $IPAddress -port $Port)) {
            Write-Error "Could not connect to adb device ${IPAddress}:$Port"; break
        }
        Write-Verbose ("setup time:   {0} ms" -f $startTime.ElapsedMilliseconds)
    }

    process {
        $processed++
        if (-not ($PSCmdlet.ShouldProcess("$Source", "PUSH"))) {return}

        $out = [PSCustomObject]@{
            Source = $Source
            RemotePath = $null
            ErrorInfo = $null
            Succeeded = $false
            Skipped = $false
            Failed = $false
        }
        Write-Verbose "processing:   $Source"
        # ensure file exists before push
        if (-not (Test-Path -Path $Source )) {
            $skipped++
            $out.Skipped = $true
            return $out
        }
        
        # push file to device
        $timer.Restart()
        $output = adb push "$Source" "$Destination" 2> $err
        if ($output | Confirm-AdbPushSuccessful) {
            $successful++
            $out.Succeeded = $true
            $out.RemotePath = "$Destination/{0}" -f $Source | Split-Path -Leaf
        } else {
            $failed++
            $out.Failed = $true
            $out.ErrorInfo = $err
        }

        Write-Verbose ("push time:     {0} ms" -f $timer.ElapsedMilliseconds); $timer.Restart()
        return $out
    }

    end {
        # print summary information (execution time, successful, )
        if ($NoSummary) {return}
        if (-not $processed) {return}
        Write-Host -NoNewLine "Finished, $processed processed"
        if ($successful) {Write-Host -NoNewLine -ForegroundColor Green " $successful successful"}
        if ($failed) {Write-Host -NoNewLine -ForegroundColor Red " $failed failed"}
        Write-Host (" in {0}" -f $startTime.Elapsed)
    }
}

# parses the output of a push to see if it was successful
# returns true if the push was successful, false otherwise
function Confirm-AdbPushSuccessful {
    Param([Parameter(ValueFromPipeline)]$data)
    Write-Debug $data
    $errored = $data.ToLower().Contains('adb: error:')
    return -not $errored
}


# ensures adb device is connected, checking status and attempting connection if not already present
# returns true if adb device is connected, false otherwise
function Confirm-AdbDeviceConnected {
    [CmdletBinding()]
    Param(
        [IPAddress]$IPAddress = "192.168.1.30",
        [int]$Port = "5555"
    )
    if (Get-AdbDeviceConnectionStatus -IP $IPAddress -Port $Port) {return $true}
    Write-Verbose "adb was not connected, attempting new connection to ${IPAddress}:$Port"
    $null = adb tcpip $Port 2> $null
    $null = adb connect ${IPAddress}:${Port} 2> $null
    return Get-AdbDeviceConnectionStatus -IP $IPAddress -Port $Port
}

# checks if adb device is connected
# returns true if adb device is connected, false otherwise
function Get-AdbDeviceConnectionStatus {
    [CmdletBinding()]
    Param(
        [IPAddress]$IPAddress = "192.168.1.30",
        [int]$Port = "5555"
    )
    Write-Verbose "checking adb connection status for ${IPAddress}:$Port"
    $devices = adb devices 2> $null
    $connected = $devices | Select-Object -Skip 1 | Where-Object {$_.Contains("${IPAddress}:$Port")}
    return [bool]$connected
}

# caches config data in script-level variable before returning key's value
function Get-Cfg {
    param($key)
    if (-not ($script:config)) {
        Write-Verbose "loading config data from $cfgFile"
        $data = (Get-Content $cfgFile) -join "`n"
        $script:config = ConvertFrom-StringData $data
    }
    Write-Verbose "${key}: ${$script:config.$key}"
    return $script:config."$key"
}

Export-ModuleMember -Function Send-AdbFile, Get-AdbDeviceConnectionStatus, Confirm-AdbDeviceConnected -Alias saf
