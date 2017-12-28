
<#PSScriptInfo

.VERSION 1.4

.GUID fe3d3698-52fc-40e8-a95c-bbc67a507ed1

.AUTHOR Adam Bertram

.COMPANYNAME Adam the Automator, LLC

.COPYRIGHT 

.DESCRIPTION This function tests various registry values to see if the local computer is pending a reboot.

.TAGS 

.LICENSEURI 

.PROJECTURI 

.ICONURI 

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS 

.EXTERNALSCRIPTDEPENDENCIES 

.RELEASENOTES

.SYNOPSIS
	This function tests various registry values to see if the local computer is pending a reboot
.NOTES
    Inspiration from: https://gallery.technet.microsoft.com/scriptcenter/Get-PendingReboot-Query-bdb79542
    Credential handling inspired by http://duffney.io/AddCredentialsToPowerShellFunctions

    Edited by JBLewis (@AspenForester)
.EXAMPLE
    PS> Test-PendingReboot -computername itfsrpw003
    
    IsPendingReboot ComputerName
    --------------- ------------
               True itfsrpw003
	
    This example checks various registry values to see if the local computer is pending a reboot.
.EXAMPLE
    PS> Test-PendingReboot -computername itfsrpw003 -Quiet

    True
    The Quiet switch limits the output to a simple True or False
#>
Function Test-PendingReboot
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $ComputerName,
	
        [Parameter()]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]::Empty,

        # Reduces output to simple boolean
        [Parameter()]
        [Switch]
        $Quiet
    )
    process
    {
        $ErrorActionPreference = 'Stop'
        try
        {
            foreach ($computer in $ComputerName)
            {
                $connParams = @{
                    'ComputerName' = $computer
                }
                if ($PSBoundParameters.ContainsKey('Credential'))
                {
                    $connParams.Credential = $Credential
                }

                $output = @{
                    ComputerName    = $computer
                    IsPendingReboot = $false
                }

                $cimSession = New-CimSession @connParams
                $OperatingSystem = Get-CimInstance -CimSession $cimSession -ClassName Win32_OperatingSystem -Property BuildNumber, CSName

                $Session = New-PSSession @connParams
                $ICSplat = @{
                    Session = $Session
                }
            
                # If Vista/2008 & Above query the CBS Reg Key
                If ($OperatingSystem.BuildNumber -ge 6001 -and (Invoke-Command @ICSplat -ScriptBlock { Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing' -Name 'RebootPending' -ErrorAction SilentlyContinue }))
                {
                    Write-Verbose -Message 'Reboot pending detected in the Component Based Servicing registry key'
                    $output.IsPendingReboot = $true
                }
                elseif (Invoke-Command @ICSplat -ScriptBlock { Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update' -Name 'RebootRequired' -ErrorAction SilentlyContinue })
                {
                    Write-Verbose -Message 'WUAU has a reboot pending'
                    $output.IsPendingReboot = $true
                }
                elseif (Invoke-Command @ICSplat -ScriptBlock { Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue } -OutVariable 'PendingReboot')
                {
                    if ($PendingReboot.PendingFileRenameOperations)
                    {
                        Write-Verbose -Message 'Reboot pending in the PendingFileRenameOperations registry value'
                        $output.IsPendingReboot = $true
                    }
                } 
                elseif (Invoke-Command @ICSplat -ScriptBlock { (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -ErrorAction SilentlyContinue).Computername -ne (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\computername' -ErrorAction SilentlyContinue).Computername}) 
                {
                    Write-Verbose -Message 'Computer name change is pending'
                    $output.IsPendingReboot = $true
                }

                If ($PSBoundParameters.ContainsKey('Quiet'))
                {
                    Write-Output $output.IsPendingReboot
                }
                else
                {
                    [pscustomobject]$output
                }
            }
        }
        catch
        {
            Write-Error -Message $_.Exception.Message
        }
    }
    end
    {
        $Session | Remove-PSSession
        $ErrorActionPreference = 'Continue'
    }
}
