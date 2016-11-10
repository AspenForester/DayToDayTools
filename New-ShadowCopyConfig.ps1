Function New-ShadowCopyConfig
{
<#
.Synopsis
   Creates a shadowstorage object on the target machine and schedules the default
   0700 and 1200 Volume Shadow Copies
.DESCRIPTION
   Long description
.EXAMPLE
   Example of how to use this cmdlet
.EXAMPLE
   Another example of how to use this cmdlet
.NOTES
   TODO: Find and correct the issue leading to the volume appearing to be disabled for shadowcopies in the GUI
#>
    [CmdletBinding()]
    Param
    (
        # Param1 help description
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        [string]
        $ComputerName = $env:COMPUTERNAME,

        # Path of volume to protect with a new shadow copy schedule
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=1)]
        [string]
        $Path,

        # Path of volume to protect with a new shadow copy schedule
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$true,
                   Position=2)]
        [string]
        $StoragePath = $Path
    )

Begin
    {
    }
Process
    {
    $cs = New-CimSession -ComputerName $ComputerName
    $Volumes = Get-CimInstance -Class Win32_Volume -CimSession $cs

    $DiffVolume = $Volumes | Where Name -EQ $StoragePath

    $PathDriveLetter = $Path[0]
    $ShareVolumeCount = ($Volumes | Where Name -Like "$PathDriveLetter*").count

    $TargetVolume = $Volumes | Where Name -Like "*$Path*"

    # Calculate / Choose MaxSpace
    if (($TargetVolume.Capacity / 10) -gt ($DiffVolume.Capacity / $ShareVolumeCount))
        {
        $MaxSpace = ($DiffVolume.Capacity / $ShareVolumeCount)
        }
    Else
        {
        $MaxSpace = ($TargetVolume.Capacity / 10)
        }
    [Uint64]$MaxSpace = [math]::Round($MaxSpace,0)

    Write-Verbose "MaxSize will be $MaxSpace" -Verbose

    $ShadowStorageParam = @{Volume     = $TargetVolume.Name
                            DiffVolume = $DiffVolume.Name
                            MaxSpace   = $MaxSpace}

    # Create the ShadowStorage
    Invoke-CimMethod -ClassName Win32_ShadowStorage -MethodName Create -CimSession $cs -Arguments $ShadowStorageParam
    Write-Verbose "Shadow Storage created" -Verbose

    # Schedule the Shadow Copies 

    $ActionParams = @{Execute          = "C:\Windows\system32\vssadmin.exe"
                      Argument         = "Create Shadow /AutoRetry=15 /For=$($TargetVolume.DeviceID)"
                      WorkingDirectory = "%systemroot%\system32"
                    }
# Need to add an author if possible AND RunWithHighestPrivileges
# Uncheck the AC power only settings
    $TaskAction = New-ScheduledTaskAction @ActionParams
    $TaskTriggerAM = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday, Tuesday, Wednesday, Thursday, Friday -At (get-date 07:00:01) 
    $TaskTriggerPM = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday, Tuesday, Wednesday, Thursday, Friday -At (get-date 12:00:01)
    $Principal = New-ScheduledTaskPrincipal "System"
    $TaskSettings = New-ScheduledTaskSettingsSet 
    $TaskName = "ShadowCopyVolume$($TargetVolume.DeviceID.TrimStart('\\?\Volume').Trim('\') )"

    Register-ScheduledTask -TaskName $TaskName `
                           -Action $TaskAction `
                           -Principal $Principal `
                           -Trigger $TaskTriggerAM, $TaskTriggerPM `
                           -Settings $TaskSettings `
                           -CimSession $cs

# IF things go wrong creating the task, check HKLM\Software\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks and \Tree
    Write-Verbose "Scheduled Task created" -Verbose

    Remove-CimSession $cs | Out-Null
# For Testing:
# vssadmin delete shadowstorage /for=<path> [/on=<path>] [/quiet]
    }
End
    {   
    }
}