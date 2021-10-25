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
        [Object][Parameter(Mandatory, ValueFromPipeline, Position=0)]
        $Source,

        # The directory on the adb device where source file(s) should be written
        #   e.g. /storage/emulated/0/Download
        [String][Parameter(Position=1)]
        [ValidateScript({Test-Path -IsValid $_}, ErrorMessage = "{0} is not a valid path")]
        [ArgumentCompleter({Get-Cfg Destination})]
        $Destination = (Get-Cfg Destination),

        # The IP address of the adb device that should be written to
        [IPAddress]
        [ArgumentCompleter({Get-Cfg IPAddress})]
        $IPAddress = (Get-Cfg IPAddress),

        # The port of the adb device that should be written to
        [Int][ValidateRange("Positive")]
        [ArgumentCompleter({Get-Cfg Port})]
        $Port = (Get-Cfg Port),

        # Disable the summary of items (successful/failed count, exec time) after processing is finished
        [Switch]
        $NoSummary
    )

    begin {
        # ensure proper device connection before running
        if (-not (Confirm-AdbDeviceConnected -IP $IPAddress -port $Port)) {
            Write-Error "Could not connect to adb device ${IPAddress}:$Port"; break
        }

        Write-Verbose "adb device:   ${IPAddress}:$Port"
        Write-Verbose "destination:  $destination"

        $startTime = [System.Diagnostics.Stopwatch]::StartNew()
        $successCount, $failCount = 0, 0

        # enable rwx trace for adb for progress tracking
        $env:ADB_TRACE = "rwx"
    }

    process {
        # support -Confirm and -WhatIf
        $remoteFile = "$Destination/$(Split-Path -Leaf $Source)"
        if (-not ($PSCmdlet.ShouldProcess("PUSH", "$Source -> $remoteFile"))) {return}
        
        # verify file exists before attemping push
        $result = [Result]::new($Source, $remoteFile)
        if (-not ($file = Get-Item -LiteralPath $Source -ErrorAction "SilentlyContinue")) {
            $result.ErrorInfo = "file does not exist: $Source"
            return $result
        }

        # start push with progress monitoring
        try {
            $result.Succeeded = adb push "$Source" "$Destination" 2>&1
            | Write-AdbPushProgress -File $File
            | Confirm-AdbPushSuccessful
        } catch {
            $result.ErrorInfo = $_
        }
        $result.Succeeded ? $successCount++ : $failCount++ > $null
        return $result
    }

    end {
        $env:ADB_TRACE = ""
        # print summary information (execution time, successful, failed)
        if ($NoSummary -or $processCount -eq 0) {return}
        Write-Host -NoNewLine "Finished:"
        Write-Host -NoNewLine " $successCount succeeded" -ForegroundColor ($successCount ? "Green" : "DarkGray")
        Write-Host -NoNewLine " $failCount failed" -ForegroundColor ($failCount ? "Red" : "DarkGray")
        Write-Host " in $($startTime.Elapsed)"
    }
}

# parses the output of a push to see if it was successful
# returns true if the push was successful, false otherwise
function Confirm-AdbPushSuccessful([Parameter(ValueFromPipeline)]$data) {
    if ([string]::IsNullOrWhiteSpace($data)) {return $false}
    $errored = $data.ToLower().Contains('adb: error:')
    if ($errored) {Write-Error $data}
    return -not $errored
}

# receives adb debug output and parses it into progress information
# the environment variable `ADB_TRACE` must be set to "wrx" or "all" before running adb
function Write-AdbPushProgress {
    Param(
        [String][Parameter(Mandatory, ValueFromPipeline)]
        $inputobject,

        [System.IO.FileInfo]
        $File
    )
    begin {
        $sum, $lastSum, $runningAverage = 0, 0, 0
        $writeDelayMS = 250
        $averageSamples = 5
        $size = $File.Length
        $Progress = @{
            PercentComplete = 0
            Status = $File.FullName
            Activity = "Pushing..."
            Id = 0
        }
        $writeTime = [System.Diagnostics.Stopwatch]::StartNew()
    }

    process {
        # force errors to throw instead of continuing
        if ($inputobject.StartsWith("adb: error:")) {
            throw "$inputobject"
        # parse push data line
        } elseif ($inputobject.Contains("writex") -and $inputobject.Contains("DATA")) {
            if ($inputobject -match "writex:.*len=(\d+).* DATA") {
                $sum += [int]$Matches[1]
                
                # only write-progress every 1/4 second
                if ($writeTime.ElapsedMilliseconds -lt $writeDelayMS) {return}
                $writeTime.Restart()
                
                # calculate running average before every progress write
                $pushedPerSecond = ($sum - $lastSum) * (1000 / $writeDelayMS)
                $lastSum = $sum
                $runningAverage = ($runningAverage * ($averageSamples - 1) + $pushedPerSecond) / $averageSamples
                $Progress.PercentComplete = ($sum/$size) * 100
                $secondsRemaining = ($size - $sum) / $runningAverage
                $Progress.Status = "[{0:00}%] [~{1:00.00}MB/s] $File.FullName" -f $Progress.PercentComplete, ($runningAverage / 1MB)
                Write-Progress @Progress -SecondsRemaining $secondsRemaining
            }

        # pass anything that isn't an error or debug message down the pipeline
        } elseif (-not ($inputobject.StartsWith("adb"))) {
            $inputobject
        } 
    }
}

# returns true if adb is available and executable, false otherwise
function Confirm-AdbAvailable {
    $result = Get-Command "adb" -ErrorAction SilentlyContinue
    if ($result) {Write-Verbose "adb:          $($result.Source)"}
    return [bool]$result
}


# ensures adb device is connected, checking status and attempting connection if not already present
# returns true if adb device is connected, false otherwise
function Confirm-AdbDeviceConnected {
    [CmdletBinding()]
    Param([IPAddress]$IPAddress = (Get-Cfg IPAddress), [int]$Port = (Get-Cfg Port))

    # confirm adb exists before checking connection
    if (-not (Confirm-AdbAvailable)) {Write-Error "adb not available in PATH, see README for install instructions"; return $false}
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
    Param([IPAddress]$IPAddress = (Get-Cfg IPAddress), [int]$Port = (Get-Cfg Port))
    Write-Verbose "checking adb connection status for ${IPAddress}:$Port"

    $devices = adb devices 2> $null
    $connected = $devices | Select-Object -Skip 1 | Where-Object {$_.Contains("${IPAddress}:$Port")}
    return [bool]$connected
}

# caches config data in script-level variable before returning key's value
function Get-Cfg($key) {
    if (-not ($script:config)) {
        Write-Verbose "loading config data from $cfgFile"
        $script:config = ConvertFrom-StringData ((Get-Content $cfgFile) -join "`n")
    }
    Write-Verbose "${key}: ${$script:config.$key}"
    return $script:config."$key"
}

class Result {
    [string]$Source
    [string]$RemotePath
    [bool]$Succeeded = $false
    [string]$ErrorInfo = $null

    Result ($Source, $Destination) {
       $this.Source = $Source
       $this.RemotePath = $Destination
    }
}

Export-ModuleMember -Function * -Alias saf
