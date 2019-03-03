<#
.SYNOPSIS
    Iterates through failed jobs on a local DPM server and run a consistency check one at a time
.DESCRIPTION
    Sleeps a minute in between checking jobs in progress
.NOTES
    Thanks to https://charbelnemnom.com/2017/09/powershell-script-for-consistency-check-when-replica-is-inconsistent-dpm-scdpm-powershell/
#>

$DPMServername = $env:COMPUTERNAME

$ReplicaErrors = Get-DPMAlert -DPMServerName $DPMServername | Where-Object {$_.Severity -eq "Error" }

write-host "Found" $ReplicaErrors.length "errors"

foreach ($ReplicaError in $ReplicaErrors) {

    Write-Host "Next up:" $ReplicaError.TargetObjectName

    # Loop until any current jobs finish
    Do {

        $CurrentJobs = Get-DPMJob -Status InProgress

        if ($CurrentJobs.length -eq 0) {
            Write-Host "Starting" $ReplicaError.TargetObjectName
            Start-DPMDatasourceConsistencyCheck -Datasource $ReplicaError.Datasource
        }
        Write-Host "Job in progress, waiting a minute"
        Start-Sleep -s 60

    } While ($CurrentJobs.length -gt 0 )

}
