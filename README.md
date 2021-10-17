# adb-powershell
This is an unofficial PowerShell wrapper for [Android Debug Bridge](https://developer.android.com/studio/command-line/adb) (`adb`). It adds pipeline support, named parameters, error handling, and output as powershell objects. 

It currently only supports `Send-AdbFile`.   
The intent is to add functions `Read-AdbFile` and `Remove-AdbFile` 

## Requirements
PowerShell (Written with 7.0.x, but may work on older versions)

`adb` must be present on the system path. I recommend installing with [scoop](https://scoop.sh/).  
`scoop install adb`

You must setup adb over wifi at least once before this will work. See the ADB page above for setup instructions. 

## Installation
This isn't ready for Powershell Gallery yet, so the best way would be to run:  
```powershell
git clone [URL] "${env:UserProfile}\Documents\Powershell\Modules\adb-powershell"
```
This will clone the repo into the module directory for the current user. Restart Powershell to automatically load. 

## Configuration
`adb-powershell` will load default values for `-IPAddress`, `-Port`, and `-Destination` if they are not set at runtime.

These defaults are loaded from `adb_defaults.cfg` from the same directory the script is stored in.

## Usage
Sends a file to the default directory on the default adb device. Defaults can be set in `adb_defaults.cfg`.
```powershell
Send-AdbFile C:\test.log
```

Same as previous, but with a specific IP and port for the adb device.
```powershell
Send-AdbFile C:\test.log -IPAddress 192.168.1.60 -Port 5555
```

Sends a file to a specific directory on the default adb device.
```powershell 
Send-AdbFile C:\test.log /storage/emulated/0/Download
```

Same as previous, but using named params. 
```powershell
Send-AdbFile -Source C:\test.log -Destination /storage/emulated/0/Download
```

Send all mp3 files in the current directory to your phone's music directory
```powershell
Get-ChildItem *.mp3 | Send-AdbFile -d /storage/emulated/0/Music  
```

Send a list of files to the default destination and limit the output to any that didn't succeed
```powershell
Send-AdbFile -Source $fileList | Where-Object {-not $_.Succeeded}
```

## License
This software uses the MIT license. Full details can be found in `LICENSE.md`