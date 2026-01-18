# Enrollment Sync - Technical Reference

## Purpose

This script synchronizes enrollment data to Active Directory security groups and generates a physical access control file for card access systems. It is designed to run on a scheduled basis (e.g., nightly) to keep group memberships and building access permissions current.

## Directory Structure

```
EnrollmentSync/
├── input/
│   ├── CourseEnrollmentData_YYYY-MM-DD.csv   # Dated enrollment data
│   └── AccessMappings.csv                     # Physical access rules (not dated)
├── output/
│   ├── ClearanceUpload_YYYY-MM-DD.csv        # Physical access output
│   └── ADGroupMembership_YYYY-MM-DD.json     # WhatIf mode only
└── Logs/
    └── sync-errors.log                        # Created only if errors occur
```

## Input Files

### CourseEnrollmentData_{date}.csv (Enrollment Data)

**Required Columns:**
- `SUBJECTCODE` - Subject abbreviation (e.g., MATH, ENGL, PHYS)
- `COURSENUMBER` - Course number (e.g., 101, 202A, 3310)
- `SECTIONNUMBER` - Section identifier (e.g., 001, A, Lab01)
- `STUDENTACCOUNT` - Member's Active Directory username (sAMAccountName)
- `STUDENTID` - Member's unique identifier for physical access systems

**Date in Filename:**
If the filename contains a date in `YYYY-MM-DD` format (e.g., `CourseEnrollmentData_2026-01-14.csv`), that date is used for output filenames. Otherwise, the current date is used.

**Example:**
```csv
SUBJECTCODE,COURSENUMBER,SECTIONNUMBER,STUDENTACCOUNT,STUDENTID
MATH,101,001,jsmith,10000001
MATH,101,002,bjones,10000002
ENGL,200,A,jsmith,10000001
```

See [samples/input/CourseEnrollmentData_2026-01-14.csv](samples/input/CourseEnrollmentData_2026-01-14.csv) for a complete example.

### AccessMappings.csv (Physical Access Permissions)

**Required Columns:**
- `SUBJECTCODE` - Subject abbreviation
- `COURSENUMBER` - Course number (optional - leave blank for subject-wide access)
- `SECTIONNUMBER` - Section identifier (optional - leave blank for course-wide access)
- `CLEARANCE` - Access clearance code to grant (e.g., CHEM_LAB_A, STUDIO_3)

**Hierarchical Matching Logic:**
- If only `SUBJECTCODE` is populated: Clearance applies to ALL enrollments with that subject
- If `SUBJECTCODE` + `COURSENUMBER` populated: Clearance applies to ALL sections of that course
- If all three fields populated: Clearance applies only to that specific section

**Example:**
```csv
SUBJECTCODE,COURSENUMBER,SECTIONNUMBER,CLEARANCE
CHEM,,,CHEM_BUILDING
CHEM,210,,CHEM_LAB_GENERAL
CHEM,310,001,CHEM_LAB_ADVANCED
ART,,,ART_STUDIO
```

See [samples/input/AccessMappings.csv](samples/input/AccessMappings.csv) for a complete example.

## Output Files

### ClearanceUpload_{date}.csv (Physical Access Control)

**Format:**
- `STUDENTID` - Member's unique identifier
- `CLEARANCE` - Access clearance code

**Notes:**
- Each member may appear multiple times (one row per clearance)
- Duplicate ID+Clearance combinations are automatically removed
- This file is typically fed into a physical access control system

**Example:**
```csv
STUDENTID,CLEARANCE
10000001,CHEM_BUILDING
10000001,CHEM_LAB_GENERAL
10000002,ART_STUDIO
```

See [samples/output/ClearanceUpload_2026-01-14.csv](samples/output/ClearanceUpload_2026-01-14.csv) for expected output.

### ADGroupMembership_{date}.json (WhatIf Mode Only)

Generated only when running with `-WhatIf`. Contains detailed information about proposed changes:

```json
{
  "metadata": {
    "generatedAt": "2026-01-14T02:00:00",
    "sourceFile": "CourseEnrollmentData_2026-01-14.csv",
    "targetOU": "OU=EnrollmentGroups,OU=Groups,DC=example,DC=edu",
    "mode": "WhatIf",
    "totalGroups": 8,
    "groupsWithChanges": 6
  },
  "groups": [
    {
      "name": "Student Enrolled in MATH",
      "level": "Subject",
      "currentMembers": ["jsmith", "oldstudent"],
      "proposedMembers": ["jsmith", "mjohnson", "bjones"],
      "toAdd": ["mjohnson", "bjones"],
      "toRemove": ["oldstudent"],
      "summary": {
        "currentCount": 2,
        "proposedCount": 3,
        "addCount": 2,
        "removeCount": 1
      }
    }
  ],
  "totals": {
    "totalMembersToAdd": 15,
    "totalMembersToRemove": 2,
    "unchangedGroups": 2
  }
}
```

See [samples/output/ADGroupMembership_2026-01-14.json](samples/output/ADGroupMembership_2026-01-14.json) for a complete example.

---

## Script Processing Flow

### Step 1: Load Data and Determine Date
```
EXTRACT date from input filename (pattern: _YYYY-MM-DD)
    IF found: use for output filenames
    ELSE: use current date

IMPORT enrollment CSV → enrollmentData
IMPORT access mappings CSV → accessMappings
```

### Step 2: Discover and Parse Active Directory Groups
```
QUERY Active Directory OU for existing security groups
FOR EACH group in Active Directory:
    PARSE group name using configurable regex patterns:
        Pattern 1: Subject-level groups (e.g., "Student Enrolled in MATH")
        Pattern 2: Course-level groups (e.g., "Student Enrolled in MATH 101")
        Pattern 3: Section-level groups (e.g., "Student Enrolled in MATH 101 Section 001")
    STORE parsed information (subject, course, section, group level)
```

### Step 3: Process Enrollment Data (Single Pass)
```
INITIALIZE empty collections for:
    - desiredMemberships (which members should be in which AD groups)
    - accessAssignments (which members get which clearances)

FOR EACH enrollment record:
    EXTRACT: subjectCode, courseNumber, sectionNumber, memberAccount, memberID

    # Part A: Determine AD Group Memberships (Hierarchical)
    FIND all matching AD groups at three levels:
        - Level 1: Groups matching just the subject code
        - Level 2: Groups matching subject + course number
        - Level 3: Groups matching subject + course + section

    FOR EACH matching group:
        ADD memberAccount to that group's desired membership list

    # Part B: Determine Physical Access Clearances (Hierarchical)
    FOR EACH access mapping rule:
        CHECK if this enrollment matches the mapping rule
        IF matched:
            ADD (memberID, clearance) to access assignments (deduplicated)
```

**Key Behavior:** If a member is enrolled in "MATH 101 Section 001" and all three group levels exist:
- Member is added to "Student Enrolled in MATH"
- Member is added to "Student Enrolled in MATH 101"
- Member is added to "Student Enrolled in MATH 101 Section 001"

### Step 4: Synchronize Active Directory Groups
```
FOR EACH parsed AD group:
    GET current members from Active Directory
    GET desired members from our calculations (Step 3)

    CALCULATE:
        membersToAdd = desired members NOT in current members
        membersToRemove = current members NOT in desired members

    COLLECT change data for JSON export

    IF NOT WhatIf mode:
        IF membersToAdd is not empty:
            BATCH ADD all members to AD group in single operation

        IF membersToRemove is not empty:
            BATCH REMOVE all members from AD group in single operation

        UPDATE group's Description field with sync audit information
```

### Step 5: Export Outputs
```
IF WhatIf mode:
    WRITE ADGroupMembership_{date}.json with all proposed changes

WRITE ClearanceUpload_{date}.csv with all access assignments

IF any errors occurred:
    WRITE sync-errors.log
```

---

## Configuration Parameters

All parameters have sensible defaults and can be overridden:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `InputCSVPath` | `C:\EnrollmentSync\input\CourseEnrollmentData.csv` | Path to enrollment data |
| `AccessMappingPath` | `C:\EnrollmentSync\input\AccessMappings.csv` | Path to access mapping rules |
| `OutputDirectory` | `C:\EnrollmentSync\output` | Directory for output files |
| `ErrorLogPath` | `C:\EnrollmentSync\Logs\sync-errors.log` | Path for error log |
| `TargetOU` | `OU=EnrollmentGroups,OU=Groups,DC=example,DC=edu` | AD OU containing groups |
| `SubjectGroupPattern` | `^Student Enrolled in (?<Subject>[A-Z]+)$` | Regex for subject-level groups |
| `CourseGroupPattern` | `^Student Enrolled in (?<Subject>[A-Z]+) (?<Course>\S+)$` | Regex for course-level groups |
| `SectionGroupPattern` | `^Student Enrolled in (?<Subject>[A-Z]+) (?<Course>\S+) Section (?<Section>.+)$` | Regex for section-level groups |

### Custom Group Naming Patterns

The script uses regex patterns with named capture groups to parse AD group names. You can customize these to match your organization's naming conventions.

**Requirements:**
- `SubjectGroupPattern` must include `(?<Subject>...)` capture group
- `CourseGroupPattern` must include `(?<Subject>...)` and `(?<Course>...)` capture groups
- `SectionGroupPattern` must include `(?<Subject>...)`, `(?<Course>...)`, and `(?<Section>...)` capture groups

**Example - Alternative naming convention:**
```powershell
.\Sync-EnrollmentGroups.ps1 `
    -SubjectGroupPattern '^Enrolled - (?<Subject>[A-Z]+)$' `
    -CourseGroupPattern '^Enrolled - (?<Subject>[A-Z]+) (?<Course>\S+)$' `
    -SectionGroupPattern '^Enrolled - (?<Subject>[A-Z]+) (?<Course>\S+) - (?<Section>.+)$'
```

---

## Error Handling

- **Missing CSV files:** Script exits with error
- **Active Directory connection issues:** Script exits with error
- **Individual AD operations fail:** Script logs error with details and continues with other groups
- **Group name doesn't match pattern:** Script logs warning and skips that group

### Error Log Format

All errors and warnings are collected during execution and written to a timestamped log file:

```
========================================
Enrollment Sync - Error Log
========================================
Script Start: 2026-01-15 02:00:15
Script End: 2026-01-15 02:03:42
Duration: 00:03:27
Total Errors/Warnings: 3
========================================

[2026-01-15 02:01:23] [AD Group Update] Failed to add members to group 'Student Enrolled in MATH 101': Access denied | Attempted members: jsmith, bjones
[2026-01-15 02:02:15] [Group Parsing] Group 'Random Group Name' does not match expected naming pattern
[2026-01-15 02:03:10] [AD Query] Failed to retrieve members of group 'Student Enrolled in CHEM 200': Object not found
```

**Error Categories:**
- `CSV Import` - Failed to read input files
- `AD Query` - Failed to retrieve AD data
- `Group Parsing` - Groups that don't match naming conventions
- `AD Group Update` - Failed add/remove/description operations
- `CSV Export` - Failed to write output files
- `JSON Export` - Failed to write WhatIf JSON

---

## Logging Levels

The script supports PowerShell's standard logging levels:

| Flag | Output |
|------|--------|
| *(none)* | Basic progress messages |
| `-Verbose` | Detailed progress, counts, and summaries |
| `-Debug` | Every operation including each enrollment record processed |
| `-WhatIf` | Dry run - shows what changes would be made + exports JSON report |

---

## Performance Considerations

The script is designed for efficiency with large datasets:

- **Single-pass design** - Enrollment data is processed once
- **Hashtable lookups** - O(1) lookups for group matching
- **Batched AD operations** - Members added/removed in single calls per group (not per-member)
- **Reduced API calls** - From potentially thousands to dozens

**Performance benefits of batching:**
- Significantly faster execution with large member changes
- Reduced network overhead and AD server load
- Suitable for scheduled/automated execution

---

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Active Directory PowerShell module (`RSAT-AD-PowerShell`)
- Appropriate AD permissions to modify group memberships
- Read access to input CSV files
- Write access to output directory
