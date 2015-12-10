<#
    .NOTES
    ===========================================================================
     Filename              : Sync-PvsLocalStore.ps1
     Created on            : 2014-09-26
     Updated on            : 2015-11-27
     Created by            : Frank Peter Schultze
     Organization          : out-web.net
    ===========================================================================

    This script needs to be run on a system where Citrix Provisiong Service's
    command-line interface MCLI.exe is installed.

    WARNING: This script leverages robocopy's MIR switch; meaning that it may
    delete so called EXTRA files on the given member PVS server(s) that are not
    present in the local vDisk store of the given master PVS server! Therefore,
    this script makes only sense when you consequently use only one PVS server
    for vDisk maintenance. You need to keep that in mind when using this script.

    DISCLAIMER: This PowerShell module is provided "as is", without any warranty,
    whether express or implied, of its accuracy, completeness, fitness for a
    particular purpose, title or non-infringement, and none of the third-party
    products or information mentioned in the work are authored, recommended,
    supported or guaranteed by me. Further, I shall not be liable for any damages
    you may sustain by using this module, whether direct, indirect, special,
    incidental or consequential, even if it has been advised of the possibility
    of such damages.

    .SYNOPSIS
    Sync local vDisk store from a master PVS server to member PVS servers except
    for vDisks in maintenance mode.

    .DESCRIPTION
    Sync all vDisks within the local vDisk store of a master PVS server to the
    local store of one or more member PVS servers with the exception of vDisks in
    maintenance mode.
#>
[CmdletBinding()]
Param
(
    #Identifies the designated master PVS server whose local vDisk store is considered the source
    [Parameter(Mandatory=$true)]
    [String]
    $MasterServer
,
    #Identifies one ore more member PVS servers whose local vDisk store is considered the target
    [Parameter(Mandatory=$true)]
    [String[]]
    $MemberServer
,
    #The path of the local vDisk store
    [Parameter(Mandatory=$true)]
    [String]
    $StorePath
,
    #The name of on ore more vDisks to be synchronized
    [Parameter(Mandatory=$true)]
    [String[]]
    $DiskName
,
    #The name of the PVS site
    [Parameter(Mandatory=$true)]
    [String]
    $SiteName
,
    #The name of the PVS store
    [Parameter(Mandatory=$true)]
    [String]
    $StoreName
)

function ConvertTo-PvsObject
{
    [CmdletBinding(SupportsShouldProcess=$False)]
    Param
    (
        [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true)]
        $InputObject
    )
    Process
    {
        switch -regex ($InputObject) {
            '^Record\s#\d+$' {
                if ($record.Count) {
                    New-Object PSObject -Property $record
                }
                $record = @{}
            }
            '^\s{4}(?<Name>\w+):\s(?<Value>.*)' {
                $record.Add($Matches.Name, $Matches.Value)
            }
        }
    }
    End
    {
        if ($record.Count) {
            New-Object PSObject -Property $record
        }
    }
}

function Get-PvsDiskVersion
{
    Param
    (
        $DiskLocatorName,
        $SiteName,
        $StoreName,
        $Type
    )
    $mcliParams = @(
        'Get', 'DiskVersion', '/p',
        "diskLocatorName=${DiskLocatorName}",
        "siteName=${SiteName}",
        "storeName=${StoreName}",
        "type=${Type}"
    )
    $mcliOutput = & "${env:ProgramFiles}\Citrix\Provisioning Services\MCLI.EXE" @mcliParams
    $mcliOutput | ConvertTo-PvsObject
}

Set-Variable -Name C_PVS_DISKTYPE_MAINTENANCE -Value '1' -Option ReadOnly

if ($MasterServer -eq $env:COMPUTERNAME)
{
    $SourcePath = $StorePath
}
else
{
    $SourcePath = '\\{0}\{1}' -f $MasterServer, $StorePath.Replace(':', '$')
}
$TargetPath = @()
$MemberServer | ForEach-Object {
    if ($_ -eq $env:COMPUTERNAME)
    {
        $TargetPath += $StorePath
    }
    else
    {
        $TargetPath += '\\{0}\{1}' -f $_, $StorePath.Replace(':', '$')
    }
}

foreach ($DiskLocatorName in $DiskName) {
    $Params = @{
        DiskLocatorName = $DiskLocatorName
        SiteName = $SiteName
        StoreName = $StoreName
        Type = $C_PVS_DISKTYPE_MAINTENANCE
    }
    $vDisk = Get-PvsDiskVersion @Params
    if ($vDisk)
    {
        $VhdFileName = $vDisk.diskFileName.TrimEnd('avhd') + '*'
        $RobocopyExcludes = '*.lok', $VhdFileName
    }
    else
    {
        $RobocopyExcludes = '*.lok'
    }

    $TargetPath | ForEach-Object {
        #remove '/L' in order to let robocopy actually copy and delete EXTRA files
        $RobocopyParam = $SourcePath, $_, "${DiskLocatorName}*", '/L', '/MIR', '/R:1', '/W:1', '/XF', $RobocopyExcludes
        & "${env:SystemRoot}\system32\robocopy.exe" @RobocopyParam
    }
}
