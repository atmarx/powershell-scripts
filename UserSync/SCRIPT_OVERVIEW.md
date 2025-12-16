# Course Enrollment Synchronization Script - Overview

## Purpose
This script synchronizes course enrollment data to Active Directory security groups and generates a physical access control file for card access systems. It is designed to run nightly to keep group memberships and building access permissions up to date.

## Input Files

### 1. input.csv (Course Enrollment Data)
**Required Columns:**
- `SUBJECTCODE` - Subject abbreviation (e.g., MATH, ENGL, PHYS)
- `COURSENUMBER` - Course number (e.g., 101, 202A, 3310)
- `SECTIONNUMBER` - Section identifier (e.g., 001, A, Lab01)
- `STUDENTACCOUNT` - Student's Active Directory username (samAccountName)
- `STUDENTID` - Student's 8-digit numeric ID

**Expected Volume:** ~100,000 records per run

**Example:**
```
SUBJECTCODE,COURSENUMBER,SECTIONNUMBER,STUDENTACCOUNT,STUDENTID
MATH,101,001,jsmith,12345678
MATH,101,002,bjones,23456789
ENGL,200,A,jsmith,12345678
```

### 2. AccessMapping.csv (Physical Access Permissions)
**Required Columns:**
- `SUBJECTCODE` - Subject abbreviation
- `COURSENUMBER` - Course number (optional - leave blank for subject-wide access)
- `SECTIONNUMBER` - Section identifier (optional - leave blank for course-wide access)
- `CLEARANCE` - Access clearance code to grant (e.g., CHEM_LAB_A, STUDIO_3)

**Hierarchical Matching Logic:**
- If only SUBJECTCODE is filled: Clearance applies to ALL courses with that subject
- If SUBJECTCODE + COURSENUMBER filled: Clearance applies to ALL sections of that course
- If all three fields filled: Clearance applies only to that specific section

**Example:**
```
SUBJECTCODE,COURSENUMBER,SECTIONNUMBER,CLEARANCE
CHEM,,,CHEM_BUILDING
CHEM,210,,CHEM_LAB_GENERAL
CHEM,310,001,CHEM_LAB_ADVANCED
ART,,,ART_STUDIO
```

## Output Files

### output.csv (Physical Access Control)
**Format:**
- `STUDENTID` - Student's 8-digit numeric ID
- `CLEARANCE` - Access clearance code

**Notes:**
- Each student may appear multiple times (one row per clearance)
- Duplicate StudentID+Clearance combinations are automatically removed
- This file is fed directly into the card access system

**Example:**
```
STUDENTID,CLEARANCE
12345678,CHEM_BUILDING
12345678,CHEM_LAB_GENERAL
12345678,CHEM_LAB_ADVANCED
23456789,ART_STUDIO
```

## Script Processing Flow

### Step 1: Load Data
```
IMPORT input.csv → enrollmentData
IMPORT AccessMapping.csv → accessMappings
```

### Step 2: Discover and Parse Active Directory Groups
```
QUERY Active Directory OU for existing security groups
FOR EACH group in Active Directory:
    PARSE group name using three possible patterns:
        Pattern 1: "Student Enrolled in {SUBJ}"
        Pattern 2: "Student Enrolled in {SUBJ} {COURSE}"
        Pattern 3: "Student Enrolled in {SUBJ} {COURSE} Section {SECTION}"
    STORE parsed information (subject, course, section, group level)
```

### Step 3: Process Enrollment Data (Single Pass)
```
INITIALIZE empty collections for:
    - desiredMemberships (which students should be in which AD groups)
    - accessAssignments (which students get which clearances)

FOR EACH enrollment record in input.csv:
    EXTRACT: subjectCode, courseNumber, sectionNumber, studentAccount, studentID

    # Part A: Determine AD Group Memberships (Hierarchical)
    FIND all matching AD groups at three levels:
        - Level 1: Groups matching just the subject code
        - Level 2: Groups matching subject + course number
        - Level 3: Groups matching subject + course + section

    FOR EACH matching group:
        ADD studentAccount to that group's desired membership list

    # Part B: Determine Physical Access Clearances (Hierarchical)
    FOR EACH access mapping rule:
        CHECK if this enrollment matches the mapping rule:
            - If mapping has only SUBJECTCODE: Match if subjects match
            - If mapping has SUBJECTCODE + COURSENUMBER: Match if both match
            - If mapping has all three fields: Match if all three match

        IF matched:
            ADD (studentID, clearance) to access assignments (deduplicated)
```

**Key Behavior:** If a student is enrolled in "MATH 101 Section 001" and all three group levels exist:
- Student is added to "Student Enrolled in MATH"
- Student is added to "Student Enrolled in MATH 101"
- Student is added to "Student Enrolled in MATH 101 Section 001"

### Step 4: Synchronize Active Directory Groups
```
FOR EACH parsed AD group:
    GET current members from Active Directory
    GET desired members from our calculations (Step 3)

    CALCULATE:
        usersToAdd = desired members NOT in current members
        usersToRemove = current members NOT in desired members

    IF usersToAdd is not empty:
        BATCH ADD all users to AD group in single operation
        LOG operation (count and list of users)
        IF operation fails: LOG error with full user list

    IF usersToRemove is not empty:
        BATCH REMOVE all users from AD group in single operation
        LOG operation (count and list of users)
        IF operation fails: LOG error with full user list

    UPDATE group's Description field with sync audit information:
        Format: "Last synced on {date} with {count} members ({added} added, {removed} removed)"
        Example: "Last synced on 2025-12-12 15:30:45 with 237 members (5 added, 12 removed)"
```

**Notes:**
- Large-scale removals are expected and allowed (e.g., at end of term when courses end)
- Group descriptions provide quick audit trail for Accounts team to verify sync status
- **Performance:** Members are added/removed in batched operations for optimal performance with large groups

### Step 5: Export Physical Access File
```
WRITE all unique (studentID, clearance) pairs to output.csv
```

### Step 6: Generate Error Log (if needed)
```
IF any errors or warnings occurred during execution:
    CREATE error log file with:
        - Execution timestamp and duration
        - Categorized error/warning messages
        - Full context for troubleshooting
    WRITE log to ErrorLogPath
ELSE:
    No log file created (successful run)
```

## Error Handling

- **Missing CSV files:** Script exits with error, logged to error log
- **Active Directory connection issues:** Script exits with error, logged to error log
- **Individual AD operations fail:** Script logs error with details and continues with other groups
- **Group name doesn't match pattern:** Script logs warning and skips that group

### Error Log Format

All errors and warnings are collected during execution and written to a timestamped log file:

```
========================================
Course Enrollment Sync - Error Log
========================================
Script Start: 2025-12-16 02:00:15
Script End: 2025-12-16 02:03:42
Duration: 00:03:27
Total Errors/Warnings: 3
========================================

[2025-12-16 02:01:23] [AD Group Update] Failed to add members to group 'Student Enrolled in MATH 101': Access denied | Attempted users: jsmith, bjones
[2025-12-16 02:02:15] [Group Parsing] Group 'Random Group Name' does not match expected naming pattern
[2025-12-16 02:03:10] [AD Query] Failed to retrieve members of group 'Student Enrolled in CHEM 200': Object not found
```

**Error Categories:**
- `CSV Import` - Failed to read input files
- `AD Query` - Failed to retrieve AD data
- `Group Parsing` - Groups that don't match naming conventions
- `AD Group Update` - Failed add/remove/description operations
- `CSV Export` - Failed to write output files

## Logging Levels

The script supports three logging levels via PowerShell parameters:

- **Normal:** Basic progress messages
- **Verbose (-Verbose flag):** Detailed progress, counts, and summaries
- **Debug (-Debug flag):** Every operation including:
  - Before/after status for all AD operations
  - Each enrollment record being processed
  - Each group match found
  - Each access clearance assigned

## Testing Mode

**-WhatIf flag:** Shows what changes would be made without actually making them (dry-run mode)

## Configuration Parameters

All paths and settings are script parameters with defaults:

- `InputCSVPath` - Path to enrollment data (default: C:\CourseSync\input.csv)
- `AccessMappingPath` - Path to access mapping file (default: C:\CourseSync\AccessMapping.csv)
- `OutputCSVPath` - Path for physical access output file (default: C:\CourseSync\output.csv)
- `ErrorLogPath` - Path for error log file (default: C:\CourseSync\Logs\sync-errors.log)
- `TargetOU` - Active Directory OU containing course groups (default: OU=CourseGroups,OU=Students,DC=domain,DC=com)

## Performance Considerations

With ~100,000 enrollment records:
- Single-pass design minimizes iterations through enrollment data
- Hashtables provide fast lookups for group matching
- **Batched AD operations** - Members added/removed in single calls per group (not per-user)
- Optimized for scheduled/automated execution
- Expected runtime: [To be determined during testing]

**Performance Benefits of Batching:**
- Reduces AD API calls from potentially thousands to dozens
- Significantly faster execution with large member changes
- Reduced network overhead and AD server load

## Questions for Data Team

1. Can you provide sample data in the format specified above?
2. What is the expected delivery schedule for input.csv? (e.g., exported at 2 AM daily)
3. Are there any data quality checks you perform before export?
4. Should we expect any null/empty values in required fields?
5. What character encoding will the CSV files use? (UTF-8 recommended)
6. Will course/section numbers contain any special characters we should be aware of?
