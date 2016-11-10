$ComputerName = 'itinfdw002'
$Path = 'T:\Blah\Team'

$cs = New-CimSession -ComputerName $ComputerName

$Volumes = Get-CimInstance -Class Win32_Volume -CimSession $cs

$DiffVolume = $Volumes | Where Name -EQ 'D:\'

$ShareVolumeCount = ($Volumes | Where Name -Like "T*").count

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

Invoke-CimMethod -ClassName Win32_ShadowStorage -MethodName Create -CimSession $cs -Arguments $ShadowStorageParam
Write-Verbose "Shadow Storage created" -Verbose

# Do we need to immediately follow on with scheduling the tasks?
# Yes, until there is an enabled scheduled task, the shadow copy will appear to be disabled in the GUI

$ActionParams = @{Execute = "C:\Windows\system32\vssadmin.exe"
                  Argument = "Create Shadow /AutoRetry=15 /For=$($TargetVolume.DeviceID)"
                  WorkingDirectory = "%systemroot%\system32"
                 }

$TaskAction = New-ScheduledTaskAction @ActionParams
$TaskTriggerAM = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday, Tuesday, Wednesday, Thursday, Friday -At (get-date 07:00:01) 
$TaskTriggerPM = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday, Tuesday, Wednesday, Thursday, Friday -At (get-date 12:00:01)
$Principal = New-ScheduledTaskPrincipal "System"
$TaskSettings = New-ScheduledTaskSettingsSet 
#$TaskDef = New-ScheduledTask -Action $TaskAction -Principal $Principal -Trigger $TaskTriggerAM,$TaskTriggerPM -Settings $TaskSettings  -CimSession $cs

$TaskName = "ShadowCopyVolume$($TargetVolume.DeviceID.TrimStart('\\?\Volume').Trim('\') )"

Register-ScheduledTask -TaskName $TaskName `
                       -Action $TaskAction `
                       -Principal $Principal `
                       -Trigger $TaskTriggerAM,$TaskTriggerPM `
                       -Settings $TaskSettings `
                       -CimSession $cs

# IF things go wrong creating the task, check HKLM\Software\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks and \Tree
Write-Verbose "Scheduled Task created" -Verbose
Remove-CimSession $cs | Out-Null

# For Testing:
# vssadmin delete shadowstorage /for=<path> [/on=<path>] [/quiet]
