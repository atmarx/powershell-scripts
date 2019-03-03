$DPMServername = $env:COMPUTERNAME

$ReplicaErrors = Get-DPMAlert -DPMServerName $DPMServername | Where-Object {$_.Severity -eq "Error" }

write-host "Found" $ReplicaErrors.length "errors"

foreach ($ReplicaError in $ReplicaErrors) {

    Write-Host $ReplicaError.TargetObjectName

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
