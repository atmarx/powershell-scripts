#Requires -Modules ActiveDirectory

<#
MIT License

Copyright (c) 2026 Andrew Marx (andrew@xram.net)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

.SYNOPSIS
    Synchronizes enrollment data to Active Directory groups and generates physical access control files.

.DESCRIPTION
    This script processes enrollment data from a CSV file to:
    1. Update Active Directory security group memberships based on enrollments
    2. Generate a physical access control file based on enrollment and access mappings

    The script supports hierarchical group membership where members are added to all
    applicable group levels (subject, course, and section-specific groups).

    Group naming patterns are configurable via regex parameters with named capture groups.

    Output filenames are dated based on the input filename (if a date is found) or
    the current date. In WhatIf mode, a JSON file is generated showing proposed changes.

.PARAMETER InputCSVPath
    Path to the input CSV file containing enrollment data.
    Expected columns: SUBJECTCODE, COURSENUMBER, SECTIONNUMBER, STUDENTACCOUNT, STUDENTID
    If filename contains a date (e.g., CourseEnrollmentData_2026-01-14.csv), that date
    is used for output filenames.

.PARAMETER AccessMappingPath
    Path to the access mapping CSV file that defines which courses grant which clearances.
    Expected columns: SUBJECTCODE, COURSENUMBER, SECTIONNUMBER, CLEARANCE

.PARAMETER OutputDirectory
    Directory where output files will be written.
    - ClearanceUpload_{date}.csv - Physical access control file
    - ADGroupMembership_{date}.json - Proposed changes (WhatIf mode only)

.PARAMETER TargetOU
    Distinguished Name of the OU containing the enrollment security groups.

.PARAMETER ErrorLogPath
    Path where the error log file will be written. Only created if errors/warnings occur.

.PARAMETER SubjectGroupPattern
    Regex pattern with named capture group 'Subject' to match subject-level groups.
    Default: '^Student Enrolled in (?<Subject>[A-Z]+)$'

.PARAMETER CourseGroupPattern
    Regex pattern with named capture groups 'Subject' and 'Course' to match course-level groups.
    Default: '^Student Enrolled in (?<Subject>[A-Z]+) (?<Course>\S+)$'

.PARAMETER SectionGroupPattern
    Regex pattern with named capture groups 'Subject', 'Course', and 'Section' to match section-level groups.
    Default: '^Student Enrolled in (?<Subject>[A-Z]+) (?<Course>\S+) Section (?<Section>.+)$'

.EXAMPLE
    .\Sync-EnrollmentGroups.ps1 -InputCSVPath ".\input\CourseEnrollmentData_2026-01-14.csv" -WhatIf
    Performs a dry run and outputs ADGroupMembership_2026-01-14.json showing proposed changes.

.EXAMPLE
    .\Sync-EnrollmentGroups.ps1 -Verbose
    Runs with detailed progress output.

.EXAMPLE
    .\Sync-EnrollmentGroups.ps1 -SubjectGroupPattern '^Enrolled - (?<Subject>[A-Z]+)$'
    Uses a custom naming pattern for subject-level groups.

.NOTES
    Requires Active Directory PowerShell module and appropriate permissions to modify groups.

    Error Logging: All errors and warnings are collected and written to the error log file.
    The log includes timestamps, categories, and execution duration for troubleshooting.
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$false)]
    [ValidateScript({Test-Path $_ -PathType Leaf})]
    [string]$InputCSVPath = "C:\EnrollmentSync\input\CourseEnrollmentData.csv",

    [Parameter(Mandatory=$false)]
    [ValidateScript({Test-Path $_ -PathType Leaf})]
    [string]$AccessMappingPath = "C:\EnrollmentSync\input\AccessMappings.csv",

    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory = "C:\EnrollmentSync\output",

    [Parameter(Mandatory=$false)]
    [ValidatePattern('^(OU|DC)=')]
    [string]$TargetOU = "OU=EnrollmentGroups,OU=Groups,DC=example,DC=edu",

    [Parameter(Mandatory=$false)]
    [string]$ErrorLogPath = "C:\EnrollmentSync\Logs\sync-errors.log",

    [Parameter(Mandatory=$false)]
    [ValidateScript({$_ -match '\(\?<Subject>'})]
    [string]$SubjectGroupPattern = '^Student Enrolled in (?<Subject>[A-Z]+)$',

    [Parameter(Mandatory=$false)]
    [ValidateScript({$_ -match '\(\?<Subject>' -and $_ -match '\(\?<Course>'})]
    [string]$CourseGroupPattern = '^Student Enrolled in (?<Subject>[A-Z]+) (?<Course>\S+)$',

    [Parameter(Mandatory=$false)]
    [ValidateScript({$_ -match '\(\?<Subject>' -and $_ -match '\(\?<Course>' -and $_ -match '\(\?<Section>'})]
    [string]$SectionGroupPattern = '^Student Enrolled in (?<Subject>[A-Z]+) (?<Course>\S+) Section (?<Section>.+)$'
)

# Initialize error logging
$script:ErrorLog = @()
$script:StartTime = Get-Date

function Write-ErrorLog {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [string]$Category = "General"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Category] $Message"

    # Add to in-memory collection
    $script:ErrorLog += $logEntry

    # Also write to Warning stream for real-time visibility
    Write-Warning $Message
}

#region Date Extraction and Output Path Setup

# Extract date from input filename or use current date
$inputFileName = [System.IO.Path]::GetFileNameWithoutExtension($InputCSVPath)
$datePattern = '_(\d{4}-\d{2}-\d{2})'

if ($inputFileName -match $datePattern) {
    $fileDate = $matches[1]
    Write-Verbose "Extracted date from input filename: $fileDate"
} else {
    $fileDate = Get-Date -Format "yyyy-MM-dd"
    Write-Verbose "No date found in input filename, using current date: $fileDate"
}

# Ensure output directory exists
if (-not (Test-Path -Path $OutputDirectory)) {
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
    Write-Verbose "Created output directory: $OutputDirectory"
}

# Build output file paths
$clearanceOutputPath = Join-Path -Path $OutputDirectory -ChildPath "ClearanceUpload_$fileDate.csv"
$jsonOutputPath = Join-Path -Path $OutputDirectory -ChildPath "ADGroupMembership_$fileDate.json"

Write-Verbose "Clearance output path: $clearanceOutputPath"
if ($WhatIfPreference) {
    Write-Verbose "WhatIf JSON output path: $jsonOutputPath"
}

#endregion

Write-Verbose "Starting enrollment synchronization process"
Write-Debug "Parameters: InputCSV=$InputCSVPath, AccessMapping=$AccessMappingPath, OutputDir=$OutputDirectory, TargetOU=$TargetOU"
Write-Debug "Group Patterns: Subject='$SubjectGroupPattern', Course='$CourseGroupPattern', Section='$SectionGroupPattern'"

#region CSV Import and Validation

Write-Verbose "Importing enrollment data from: $InputCSVPath"
try {
    $enrollmentData = Import-Csv -Path $InputCSVPath -ErrorAction Stop
    Write-Verbose "Successfully imported $($enrollmentData.Count) enrollment records"
} catch {
    $errorMsg = "Failed to import enrollment data from $InputCSVPath : $_"
    Write-ErrorLog -Message $errorMsg -Category "CSV Import"
    Write-Error $errorMsg
    exit 1
}

Write-Verbose "Importing access mapping data from: $AccessMappingPath"
try {
    $accessMappings = Import-Csv -Path $AccessMappingPath -ErrorAction Stop
    Write-Verbose "Successfully imported $($accessMappings.Count) access mapping records"
} catch {
    $errorMsg = "Failed to import access mapping data from $AccessMappingPath : $_"
    Write-ErrorLog -Message $errorMsg -Category "CSV Import"
    Write-Error $errorMsg
    exit 1
}

#endregion

#region AD Group Discovery and Parsing

Write-Verbose "Discovering existing AD groups in OU: $TargetOU"
Write-Debug "About to query AD groups from OU: $TargetOU"

try {
    $adGroups = Get-ADGroup -SearchBase $TargetOU -Filter * -ErrorAction Stop
    Write-Debug "Successfully retrieved $($adGroups.Count) groups from AD"
    Write-Verbose "Found $($adGroups.Count) existing groups in target OU"
} catch {
    $errorMsg = "Failed to retrieve AD groups from $TargetOU : $_"
    Write-ErrorLog -Message $errorMsg -Category "AD Query"
    Write-Error $errorMsg
    exit 1
}

# Parse group names using configurable regex patterns
$parsedGroups = @()

foreach ($group in $adGroups) {
    $groupName = $group.Name

    # Try to match against our three patterns (most specific first)
    if ($groupName -match $SectionGroupPattern) {
        # Pattern 3: Subject + Course + Section
        $parsedGroups += [PSCustomObject]@{
            GroupObject = $group
            GroupName = $groupName
            SubjectCode = $matches['Subject']
            CourseNumber = $matches['Course']
            SectionNumber = $matches['Section']
            Level = 'Section'
        }
        Write-Debug "Parsed group '$groupName' as Section level: $($matches['Subject']) $($matches['Course']) Section $($matches['Section'])"
    }
    elseif ($groupName -match $CourseGroupPattern) {
        # Pattern 2: Subject + Course
        $parsedGroups += [PSCustomObject]@{
            GroupObject = $group
            GroupName = $groupName
            SubjectCode = $matches['Subject']
            CourseNumber = $matches['Course']
            SectionNumber = $null
            Level = 'Course'
        }
        Write-Debug "Parsed group '$groupName' as Course level: $($matches['Subject']) $($matches['Course'])"
    }
    elseif ($groupName -match $SubjectGroupPattern) {
        # Pattern 1: Subject only
        $parsedGroups += [PSCustomObject]@{
            GroupObject = $group
            GroupName = $groupName
            SubjectCode = $matches['Subject']
            CourseNumber = $null
            SectionNumber = $null
            Level = 'Subject'
        }
        Write-Debug "Parsed group '$groupName' as Subject level: $($matches['Subject'])"
    }
    else {
        $warnMsg = "Group '$groupName' does not match expected naming pattern and will be skipped"
        Write-ErrorLog -Message $warnMsg -Category "Group Parsing"
    }
}

Write-Verbose "Successfully parsed $($parsedGroups.Count) groups matching naming conventions"

#endregion

#region Build Desired AD Group Memberships and Physical Access Clearances

Write-Verbose "Processing enrollment data to build group memberships and access clearances"

# Create a hashtable: GroupDN -> @(MemberAccounts)
$desiredMemberships = @{}

# Use a hashtable to track unique ID+Clearance combinations
$accessAssignments = @{}

# Single pass through enrollment data
foreach ($enrollment in $enrollmentData) {
    $subj = $enrollment.SUBJECTCODE
    $course = $enrollment.COURSENUMBER
    $section = $enrollment.SECTIONNUMBER
    $memberAccount = $enrollment.STUDENTACCOUNT
    $memberID = $enrollment.STUDENTID

    Write-Debug "Processing enrollment: $memberAccount (ID: $memberID) in $subj $course Section $section"

    #region Process AD Group Memberships

    # Find all matching groups (hierarchical - match all levels)
    $matchingGroups = @()

    # Level 1: Subject only
    $matchingGroups += $parsedGroups | Where-Object {
        $_.Level -eq 'Subject' -and $_.SubjectCode -eq $subj
    }

    # Level 2: Subject + Course
    $matchingGroups += $parsedGroups | Where-Object {
        $_.Level -eq 'Course' -and $_.SubjectCode -eq $subj -and $_.CourseNumber -eq $course
    }

    # Level 3: Subject + Course + Section
    $matchingGroups += $parsedGroups | Where-Object {
        $_.Level -eq 'Section' -and $_.SubjectCode -eq $subj -and $_.CourseNumber -eq $course -and $_.SectionNumber -eq $section
    }

    # Add member to each matching group's desired membership list
    foreach ($group in $matchingGroups) {
        $groupDN = $group.GroupObject.DistinguishedName

        if (-not $desiredMemberships.ContainsKey($groupDN)) {
            $desiredMemberships[$groupDN] = @()
        }

        if ($memberAccount -notin $desiredMemberships[$groupDN]) {
            $desiredMemberships[$groupDN] += $memberAccount
            Write-Debug "Added $memberAccount to desired membership for group: $($group.GroupName)"
        }
    }

    #endregion

    #region Process Physical Access Clearances

    # Find all matching access mappings (hierarchical)
    foreach ($mapping in $accessMappings) {
        $mapSubj = $mapping.SUBJECTCODE
        $mapCourse = $mapping.COURSENUMBER
        $mapSection = $mapping.SECTIONNUMBER
        $clearance = $mapping.CLEARANCE

        $isMatch = $false

        # Match logic based on which fields are populated in the mapping
        if ([string]::IsNullOrWhiteSpace($mapCourse) -and [string]::IsNullOrWhiteSpace($mapSection)) {
            # Subject-only mapping
            if ($subj -eq $mapSubj) {
                $isMatch = $true
                Write-Debug "Matched subject-level mapping: $mapSubj -> $clearance"
            }
        }
        elseif ([string]::IsNullOrWhiteSpace($mapSection)) {
            # Subject + Course mapping
            if ($subj -eq $mapSubj -and $course -eq $mapCourse) {
                $isMatch = $true
                Write-Debug "Matched course-level mapping: $mapSubj $mapCourse -> $clearance"
            }
        }
        else {
            # Subject + Course + Section mapping
            if ($subj -eq $mapSubj -and $course -eq $mapCourse -and $section -eq $mapSection) {
                $isMatch = $true
                Write-Debug "Matched section-level mapping: $mapSubj $mapCourse Section $mapSection -> $clearance"
            }
        }

        # If matched, add to access assignments (deduplicated by key)
        if ($isMatch) {
            $key = "$memberID|$clearance"
            if (-not $accessAssignments.ContainsKey($key)) {
                $accessAssignments[$key] = [PSCustomObject]@{
                    STUDENTID = $memberID
                    CLEARANCE = $clearance
                }
                Write-Debug "Assigned clearance '$clearance' to ID $memberID"
            }
        }
    }

    #endregion
}

Write-Verbose "Processed $($enrollmentData.Count) enrollment records"
Write-Verbose "Built desired memberships for $($desiredMemberships.Count) groups"
Write-Verbose "Built $($accessAssignments.Count) unique access clearance assignments"

#endregion

#region Compare and Update AD Group Memberships

Write-Verbose "Comparing desired vs actual group memberships and applying changes"

# Collect group change data for JSON export (WhatIf mode)
$groupChangeData = @()
$totalToAdd = 0
$totalToRemove = 0
$groupsWithChanges = 0

foreach ($group in $parsedGroups) {
    $groupDN = $group.GroupObject.DistinguishedName
    $groupName = $group.GroupName

    Write-Debug "Processing group: $groupName"

    # Get current members
    Write-Debug "About to retrieve current members of group: $groupName"
    try {
        $currentMembersRaw = Get-ADGroupMember -Identity $groupDN -ErrorAction Stop
        $currentMembers = @($currentMembersRaw | Select-Object -ExpandProperty SamAccountName)
        Write-Debug "Retrieved $($currentMembers.Count) current members from group: $groupName"
    } catch {
        $errorMsg = "Failed to retrieve members of group '$groupName': $_"
        Write-ErrorLog -Message $errorMsg -Category "AD Query"
        continue
    }

    # Get desired members (or empty array if none)
    $desiredMembers = if ($desiredMemberships.ContainsKey($groupDN)) {
        @($desiredMemberships[$groupDN])
    } else {
        @()
    }

    # Calculate adds and removes
    $toAdd = @($desiredMembers | Where-Object { $_ -notin $currentMembers })
    $toRemove = @($currentMembers | Where-Object { $_ -notin $desiredMembers })

    Write-Verbose "Group '$groupName': $($toAdd.Count) to add, $($toRemove.Count) to remove"

    # Track totals
    $totalToAdd += $toAdd.Count
    $totalToRemove += $toRemove.Count
    if ($toAdd.Count -gt 0 -or $toRemove.Count -gt 0) {
        $groupsWithChanges++
    }

    # Build group change record for JSON output
    $groupChangeData += [PSCustomObject]@{
        name = $groupName
        distinguishedName = $groupDN
        level = $group.Level
        subject = $group.SubjectCode
        course = $group.CourseNumber
        section = $group.SectionNumber
        currentMembers = $currentMembers
        proposedMembers = $desiredMembers
        toAdd = $toAdd
        toRemove = $toRemove
        summary = [PSCustomObject]@{
            currentCount = $currentMembers.Count
            proposedCount = $desiredMembers.Count
            addCount = $toAdd.Count
            removeCount = $toRemove.Count
        }
    }

    # Batch add members
    if ($toAdd.Count -gt 0) {
        Write-Debug "About to add $($toAdd.Count) members to group '$groupName': $($toAdd -join ', ')"
        try {
            if ($PSCmdlet.ShouldProcess("Group: $groupName", "Add $($toAdd.Count) members")) {
                Add-ADGroupMember -Identity $groupDN -Members $toAdd -ErrorAction Stop
                Write-Debug "Successfully added $($toAdd.Count) members to group '$groupName'"
                Write-Verbose "Added $($toAdd.Count) members to $groupName"
            }
        } catch {
            $errorMsg = "Failed to add members to group '$groupName': $_ | Attempted members: $($toAdd -join ', ')"
            Write-ErrorLog -Message $errorMsg -Category "AD Group Update"
        }
    }

    # Batch remove members
    if ($toRemove.Count -gt 0) {
        Write-Debug "About to remove $($toRemove.Count) members from group '$groupName': $($toRemove -join ', ')"
        try {
            if ($PSCmdlet.ShouldProcess("Group: $groupName", "Remove $($toRemove.Count) members")) {
                Remove-ADGroupMember -Identity $groupDN -Members $toRemove -Confirm:$false -ErrorAction Stop
                Write-Debug "Successfully removed $($toRemove.Count) members from group '$groupName'"
                Write-Verbose "Removed $($toRemove.Count) members from $groupName"
            }
        } catch {
            $errorMsg = "Failed to remove members from group '$groupName': $_ | Attempted members: $($toRemove -join ', ')"
            Write-ErrorLog -Message $errorMsg -Category "AD Group Update"
        }
    }

    # Update group description with sync information (skip in WhatIf mode)
    if (-not $WhatIfPreference) {
        $syncDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $finalMemberCount = $desiredMembers.Count
        $addedCount = $toAdd.Count
        $removedCount = $toRemove.Count
        $newDescription = "Last synced on $syncDate with $finalMemberCount members ($addedCount added, $removedCount removed)"

        Write-Debug "About to update description for group '$groupName': $newDescription"
        try {
            if ($PSCmdlet.ShouldProcess("Group: $groupName", "Update description: $newDescription")) {
                Set-ADGroup -Identity $groupDN -Description $newDescription -ErrorAction Stop
                Write-Debug "Successfully updated description for group '$groupName'"
            }
        } catch {
            $errorMsg = "Failed to update description for group '$groupName': $_"
            Write-ErrorLog -Message $errorMsg -Category "AD Group Update"
        }
    }
}

Write-Verbose "AD group membership synchronization complete"

#endregion

#region Export WhatIf JSON (if applicable)

if ($WhatIfPreference) {
    Write-Verbose "WhatIf mode: Exporting proposed changes to JSON: $jsonOutputPath"

    $jsonOutput = [PSCustomObject]@{
        metadata = [PSCustomObject]@{
            generatedAt = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
            sourceFile = [System.IO.Path]::GetFileName($InputCSVPath)
            targetOU = $TargetOU
            mode = "WhatIf"
            totalGroups = $parsedGroups.Count
            groupsWithChanges = $groupsWithChanges
        }
        groups = $groupChangeData
        totals = [PSCustomObject]@{
            totalMembersToAdd = $totalToAdd
            totalMembersToRemove = $totalToRemove
            unchangedGroups = ($parsedGroups.Count - $groupsWithChanges)
        }
    }

    try {
        $jsonOutput | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonOutputPath -Encoding UTF8 -ErrorAction Stop
        Write-Verbose "Successfully exported proposed changes to: $jsonOutputPath"
        Write-Host "WhatIf: Proposed AD group changes written to: $jsonOutputPath" -ForegroundColor Cyan
    } catch {
        $errorMsg = "Failed to export WhatIf JSON to $jsonOutputPath : $_"
        Write-ErrorLog -Message $errorMsg -Category "JSON Export"
        Write-Error $errorMsg
    }
}

#endregion

#region Export Physical Access CSV

Write-Verbose "Exporting physical access control file to: $clearanceOutputPath"

try {
    $accessAssignments.Values | Export-Csv -Path $clearanceOutputPath -NoTypeInformation -ErrorAction Stop
    Write-Debug "Successfully exported $($accessAssignments.Count) access records to $clearanceOutputPath"
    Write-Verbose "Successfully exported $($accessAssignments.Count) access clearance assignments"
} catch {
    $errorMsg = "Failed to export access control file to $clearanceOutputPath : $_"
    Write-ErrorLog -Message $errorMsg -Category "CSV Export"
    Write-Error $errorMsg
}

#endregion

#region Write Error Log to File

if ($script:ErrorLog.Count -gt 0) {
    Write-Verbose "Writing $($script:ErrorLog.Count) errors/warnings to log file: $ErrorLogPath"

    try {
        # Ensure directory exists
        $logDir = Split-Path -Path $ErrorLogPath -Parent
        if (-not (Test-Path -Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }

        # Write header with run information
        $endTime = Get-Date
        $duration = $endTime - $script:StartTime
        $header = @"
========================================
Enrollment Sync - Error Log
========================================
Script Start: $($script:StartTime.ToString('yyyy-MM-dd HH:mm:ss'))
Script End: $($endTime.ToString('yyyy-MM-dd HH:mm:ss'))
Duration: $($duration.ToString('hh\:mm\:ss'))
Total Errors/Warnings: $($script:ErrorLog.Count)
========================================

"@

        # Write to log file
        $header | Out-File -FilePath $ErrorLogPath -Encoding UTF8
        $script:ErrorLog | Out-File -FilePath $ErrorLogPath -Append -Encoding UTF8

        Write-Verbose "Error log written successfully to: $ErrorLogPath"
    } catch {
        Write-Warning "Failed to write error log to $ErrorLogPath : $_"
    }
} else {
    Write-Verbose "No errors or warnings encountered during execution"
}

#endregion

Write-Verbose "Enrollment synchronization process completed successfully"
