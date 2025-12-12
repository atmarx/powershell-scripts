<#
.SYNOPSIS
    Synchronizes course enrollment data to Active Directory groups and generates physical access control file.

.DESCRIPTION
    This script processes course enrollment data from a CSV file to:
    1. Update Active Directory security group memberships based on course enrollments
    2. Generate a physical access control file based on enrollment and access mappings

    The script supports hierarchical group membership where students are added to all
    applicable group levels (subject, course, and section specific groups).

.PARAMETER InputCSVPath
    Path to the input CSV file containing course enrollment data.
    Expected columns: SUBJECTCODE, COURSENUMBER, SECTIONNUMBER, STUDENTACCOUNT, STUDENTID

.PARAMETER AccessMappingPath
    Path to the access mapping CSV file that defines which courses grant which clearances.
    Expected columns: SUBJECTCODE, COURSENUMBER, SECTIONNUMBER, CLEARANCE

.PARAMETER OutputCSVPath
    Path where the physical access control CSV file will be written.
    Output format: STUDENTID, CLEARANCE

.PARAMETER TargetOU
    Distinguished Name of the OU containing the course security groups.

.PARAMETER WhatIf
    If specified, shows what changes would be made without actually making them.

.EXAMPLE
    .\Sync-CourseEnrollmentToADAndAccess.ps1 -InputCSVPath "C:\Data\input.csv" -WhatIf

.NOTES
    Requires Active Directory PowerShell module and appropriate permissions to modify groups.
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$false)]
    [string]$InputCSVPath = "C:\CourseSync\input.csv",

    [Parameter(Mandatory=$false)]
    [string]$AccessMappingPath = "C:\CourseSync\AccessMapping.csv",

    [Parameter(Mandatory=$false)]
    [string]$OutputCSVPath = "C:\CourseSync\output.csv",

    [Parameter(Mandatory=$false)]
    [string]$TargetOU = "OU=CourseGroups,OU=Students,DC=domain,DC=com"
)

# Requires Active Directory module
Import-Module ActiveDirectory -ErrorAction Stop

Write-Verbose "Starting course enrollment synchronization process"
Write-Debug "Parameters: InputCSV=$InputCSVPath, AccessMapping=$AccessMappingPath, OutputCSV=$OutputCSVPath, TargetOU=$TargetOU"

#region CSV Import and Validation

Write-Verbose "Importing course enrollment data from: $InputCSVPath"
try {
    $enrollmentData = Import-Csv -Path $InputCSVPath -ErrorAction Stop
    Write-Verbose "Successfully imported $($enrollmentData.Count) enrollment records"
} catch {
    Write-Error "Failed to import enrollment data from $InputCSVPath : $_"
    exit 1
}

Write-Verbose "Importing access mapping data from: $AccessMappingPath"
try {
    $accessMappings = Import-Csv -Path $AccessMappingPath -ErrorAction Stop
    Write-Verbose "Successfully imported $($accessMappings.Count) access mapping records"
} catch {
    Write-Error "Failed to import access mapping data from $AccessMappingPath : $_"
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
    Write-Error "Failed to retrieve AD groups from $TargetOU : $_"
    exit 1
}

# Parse group names and create lookup structure
# Patterns:
#   "Student Enrolled in {SUBJ}"
#   "Student Enrolled in {SUBJ} {COURSE}"
#   "Student Enrolled in {SUBJ} {COURSE} Section {SECTION}"

$parsedGroups = @()

foreach ($group in $adGroups) {
    $groupName = $group.Name

    # Try to match against our three patterns
    if ($groupName -match '^Student Enrolled in ([A-Z]+) (\S+) Section (.+)$') {
        # Pattern 3: Subject + Course + Section
        $parsedGroups += [PSCustomObject]@{
            GroupObject = $group
            GroupName = $groupName
            SubjectCode = $matches[1]
            CourseNumber = $matches[2]
            SectionNumber = $matches[3]
            Level = 'Section'
        }
        Write-Debug "Parsed group '$groupName' as Section level: $($matches[1]) $($matches[2]) Section $($matches[3])"
    }
    elseif ($groupName -match '^Student Enrolled in ([A-Z]+) (\S+)$') {
        # Pattern 2: Subject + Course
        $parsedGroups += [PSCustomObject]@{
            GroupObject = $group
            GroupName = $groupName
            SubjectCode = $matches[1]
            CourseNumber = $matches[2]
            SectionNumber = $null
            Level = 'Course'
        }
        Write-Debug "Parsed group '$groupName' as Course level: $($matches[1]) $($matches[2])"
    }
    elseif ($groupName -match '^Student Enrolled in ([A-Z]+)$') {
        # Pattern 1: Subject only
        $parsedGroups += [PSCustomObject]@{
            GroupObject = $group
            GroupName = $groupName
            SubjectCode = $matches[1]
            CourseNumber = $null
            SectionNumber = $null
            Level = 'Subject'
        }
        Write-Debug "Parsed group '$groupName' as Subject level: $($matches[1])"
    }
    else {
        Write-Warning "Group '$groupName' does not match expected naming pattern and will be skipped"
    }
}

Write-Verbose "Successfully parsed $($parsedGroups.Count) groups matching naming conventions"

#endregion

#region Build Desired AD Group Memberships and Physical Access Clearances

Write-Verbose "Processing enrollment data to build group memberships and access clearances"

# Create a hashtable: GroupDN -> @(StudentAccounts)
$desiredMemberships = @{}

# Use a hashtable to track unique StudentID+Clearance combinations
$accessAssignments = @{}

# Single pass through enrollment data
foreach ($enrollment in $enrollmentData) {
    $subj = $enrollment.SUBJECTCODE
    $course = $enrollment.COURSENUMBER
    $section = $enrollment.SECTIONNUMBER
    $studentAccount = $enrollment.STUDENTACCOUNT
    $studentID = $enrollment.STUDENTID

    Write-Debug "Processing enrollment: $studentAccount (ID: $studentID) in $subj $course Section $section"

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

    # Add student to each matching group's desired membership list
    foreach ($group in $matchingGroups) {
        $groupDN = $group.GroupObject.DistinguishedName

        if (-not $desiredMemberships.ContainsKey($groupDN)) {
            $desiredMemberships[$groupDN] = @()
        }

        if ($studentAccount -notin $desiredMemberships[$groupDN]) {
            $desiredMemberships[$groupDN] += $studentAccount
            Write-Debug "Added $studentAccount to desired membership for group: $($group.GroupName)"
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
            $key = "$studentID|$clearance"
            if (-not $accessAssignments.ContainsKey($key)) {
                $accessAssignments[$key] = [PSCustomObject]@{
                    STUDENTID = $studentID
                    CLEARANCE = $clearance
                }
                Write-Debug "Assigned clearance '$clearance' to StudentID $studentID"
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

foreach ($group in $parsedGroups) {
    $groupDN = $group.GroupObject.DistinguishedName
    $groupName = $group.GroupName

    Write-Debug "Processing group: $groupName"

    # Get current members
    Write-Debug "About to retrieve current members of group: $groupName"
    try {
        $currentMembers = Get-ADGroupMember -Identity $groupDN -ErrorAction Stop |
            Select-Object -ExpandProperty SamAccountName
        Write-Debug "Retrieved $($currentMembers.Count) current members from group: $groupName"
    } catch {
        Write-Warning "Failed to retrieve members of group '$groupName': $_"
        continue
    }

    # Get desired members (or empty array if none)
    $desiredMembers = if ($desiredMemberships.ContainsKey($groupDN)) {
        $desiredMemberships[$groupDN]
    } else {
        @()
    }

    # Calculate adds and removes
    $toAdd = $desiredMembers | Where-Object { $_ -notin $currentMembers }
    $toRemove = $currentMembers | Where-Object { $_ -notin $desiredMembers }

    Write-Verbose "Group '$groupName': $($toAdd.Count) to add, $($toRemove.Count) to remove"

    # Add members
    foreach ($user in $toAdd) {
        Write-Debug "About to add user '$user' to group '$groupName'"
        try {
            if ($PSCmdlet.ShouldProcess("Group: $groupName", "Add member: $user")) {
                Add-ADGroupMember -Identity $groupDN -Members $user -ErrorAction Stop
                Write-Debug "Successfully added user '$user' to group '$groupName'"
                Write-Verbose "Added $user to $groupName"
            }
        } catch {
            Write-Warning "Failed to add user '$user' to group '$groupName': $_"
        }
    }

    # Remove members
    foreach ($user in $toRemove) {
        Write-Debug "About to remove user '$user' from group '$groupName'"
        try {
            if ($PSCmdlet.ShouldProcess("Group: $groupName", "Remove member: $user")) {
                Remove-ADGroupMember -Identity $groupDN -Members $user -Confirm:$false -ErrorAction Stop
                Write-Debug "Successfully removed user '$user' from group '$groupName'"
                Write-Verbose "Removed $user from $groupName"
            }
        } catch {
            Write-Warning "Failed to remove user '$user' from group '$groupName': $_"
        }
    }
}

Write-Verbose "AD group membership synchronization complete"

#endregion

#region Export Physical Access CSV

Write-Verbose "Exporting physical access control file to: $OutputCSVPath"

try {
    $accessAssignments.Values | Export-Csv -Path $OutputCSVPath -NoTypeInformation -ErrorAction Stop
    Write-Debug "Successfully exported $($accessAssignments.Count) access records to $OutputCSVPath"
    Write-Verbose "Successfully exported $($accessAssignments.Count) access clearance assignments"
} catch {
    Write-Error "Failed to export access control file to $OutputCSVPath : $_"
}

#endregion

Write-Verbose "Course enrollment synchronization process completed successfully"
