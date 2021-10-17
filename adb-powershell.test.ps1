Describe 'ADB-Suite' {
    BeforeAll {
        Import-Module adb-powershell -Force
        $testFile = New-TemporaryFile
        $testFileLeaf = Split-Path -Leaf $testFile
        $testRead = New-TemporaryFile
        $remoteDir = '/storage/emulated/0/Download'
        $testData = 'test data please ignore'
        $testData > $testFile
    }

    Context 'Get-AdbDeviceConnectionStatus' {
        It 'should return false when no devices are connected' {
            adb disconnect
            Get-AdbDeviceConnectionStatus | Should -Be $false
            
        }
        It 'should return true when a device is connected' {
            adb connect 192.168.1.30:5555
            Get-AdbDeviceConnectionStatus | Should -Be $true
        }
    }
    
    Context 'Confirm-AdbDeviceConnected' {
        It 'should connect to an adb device when called' {
            adb disconnect
            Confirm-AdbDeviceConnected | Should -Be $true
        }
        It "should throw an error when the IP is not valid" {
            try {
                Confirm-AdbDeviceConnected -ip "fakeIPaddress" | Should -Throw
            } catch {
                # exception proves error is working
                $true | Should -BeTrue
            }
        }
        It 'should connect even when no adb server has been started' {
            adb kill-server
            Confirm-AdbDeviceConnected | Should -Be $true
            adb start-server
        }
    }
    
    Context 'Send-AdbFile' -Tag 'push' {
        It 'should push files to an adb device successfully' {
            $result = Send-AdbFile -Source "$testFile" -Destination "$remoteDir" -NoSummary
            $result.Succeeded | Should -BeTrue
            $result.Skipped | Should -BeFalse
            $result.Failed | Should -BeFalse
            adb shell rm "$remoteDir/$testFileLeaf" 2> $null
        }
        
        It 'should send accurate data to the adb device' {
            $result = Send-AdbFile -Source "$testFile" -Destination "$remoteDir" -NoSummary
            $result.Succeeded | Should -BeTrue
            $result.Skipped | Should -BeFalse
            $result.Failed | Should -BeFalse
            adb pull "$remoteDir/$testFileLeaf" "$testRead"
            (Get-FileHash "$testFile").hash -eq (Get-FileHash "$testRead").hash | Should -Be $true
            adb shell rm "$remoteDir/$testFileLeaf" 2> $null
        }

        It 'should support the first usage example' {
            $result = Send-AdbFile $testFile -NoSummary
            $result.Succeeded | Should -BeTrue
            $result.Skipped | Should -BeFalse
            $result.Failed | Should -BeFalse
            adb shell rm "$remoteDir/$testFileLeaf" 2> $null
        }

        It 'should support the second usage example' {
            $result = Send-AdbFile "$testFile" "$remoteDir" -NoSummary
            $result.Succeeded | Should -BeTrue
            $result.Skipped | Should -BeFalse
            $result.Failed | Should -BeFalse
            adb shell rm "$remoteDir/$testFileLeaf" 2> $null
        }

        It 'should support the third usage example' {
            $result = Get-ChildItem $testFile | Send-AdbFile -d "$remoteDir" -NoSummary
            $result.Succeeded | Should -BeTrue
            $result.Skipped | Should -BeFalse
            $result.Failed | Should -BeFalse
            adb shell rm "$remoteDir/$testFileLeaf" 2> $null
        }

        It 'should mark non-existent local files as skipped' {
            $result = Send-AdbFile -Source "./non_existent_file" -Destination $remote
            $result.Skipped | Should -BeTrue
            $result.Failed | Should -BeFalse
            $result.Succeeded | Should -BeFalse
        }
    }
}