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
    }

    process {
        $remoteFile = "$Destination/$(Split-Path -Leaf $Source)"
        if (-not ($PSCmdlet.ShouldProcess("PUSH", "$Source -> $remoteFile"))) {return}
        
        # push file to adb device and record results
        $result = [Result]::new($Source, $remoteFile)
        Write-Verbose "pushing:       $Source -> $Destination"
        # TODO: add progress for long-running push
        $err = $($succeeded = adb push "$Source" "$Destination" | Confirm-AdbPushSuccessful) 2>&1
        $result.Update($succeeded, $err)
        $null = $succeeded ? $successCount++ : $failCount++        
        return $result
    }

    end {
        # print summary information (execution time, successCount, )
        if ($NoSummary -or $processCount -eq 0) {return}
        Write-Host -NoNewLine "Finished:"
        Write-Host -NoNewLine " $successCount succeeded" -ForegroundColor ($successCount ? "Green" : "DarkGray")
        Write-Host -NoNewLine " $failCount failed" -ForegroundColor ($failCount ? "Red" : "DarkGray")
        Write-Host " in $($startTime.Elapsed)"
    }
}

# parses the output of a push to see if it was successCou
# returns true if the push was successCou, false otherwise
function Confirm-AdbPushSuccessful([Parameter(ValueFromPipeline)]$data) {
    $errored = $data.ToLower().Contains('adb: error:')
    if ($errored) {Write-Error $data}
    return -not $errored
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
    [string]$ErrorInfo = $null
    [bool]$Succeeded = $false
    [bool]$Failed = $false

    Result ($Source, $Destination) {
       $this.Source = $Source
       $this.RemotePath = $Destination
    }

    Update([bool]$success, $err = $null) {
        $this.Succeeded = $success
        $this.Failed = -not $success
        $this.ErrorInfo = $err
    }
}

Export-ModuleMember -Function * -Alias saf
