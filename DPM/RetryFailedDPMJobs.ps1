<#
.SYNOPSIS
    Iterates through failed jobs on a local DPM server and run a consistency check one at a time
.DESCRIPTION
    Sleeps a minute in between checking jobs in progress
.NOTES
    Thanks to https://charbelnemnom.com/2017/09/powershell-script-for-consistency-check-when-replica-is-inconsistent-dpm-scdpm-powershell/
    for the inspiration.  Too bad my storage is too slow to just kick them all off and forget it -- I've found single file
    to be more reliable.
#>

$DPMServername = $env:COMPUTERNAME

$ReplicaErrors = Get-DPMAlert -DPMServerName $DPMServername | Where-Object {$_.Severity -eq "Error" }

write-host "Found" $ReplicaErrors.length "errors"

foreach ($ReplicaError in $ReplicaErrors) {

    Write-Host "Waiting to launch a consistency check for" $ReplicaError.TargetObjectName

    # Loop until any current jobs finish
    Do {

        $CurrentJobs = Get-DPMJob -Status InProgress

        if ($CurrentJobs.length -eq 0) {
            Write-Host "Starting a consistency check for" $ReplicaError.TargetObjectName
            Start-DPMDatasourceConsistencyCheck -Datasource $ReplicaError.Datasource
        }
        Write-Host "Found jobs already in progress -- going to sleep for a minute."
        Start-Sleep -s 60

    } While ($CurrentJobs.length -gt 0 )

}
