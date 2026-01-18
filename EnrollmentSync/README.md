# EnrollmentSync

Automates Active Directory group membership based on enrollment data, with optional physical access control file generation.

## What It Does

- **Reads** enrollment data from CSV (e.g., course registrations, program enrollments)
- **Syncs** AD security group memberships based on hierarchical matching
- **Generates** physical access control files for card access systems
- **Logs** all changes with audit trail in group descriptions
- **Exports** proposed changes as JSON in WhatIf mode for review

## Quick Start

```powershell
# Dry run - see what would change (outputs JSON report)
.\Sync-EnrollmentGroups.ps1 `
    -InputCSVPath ".\input\CourseEnrollmentData_2026-01-14.csv" `
    -WhatIf -Verbose

# Run with default paths
.\Sync-EnrollmentGroups.ps1

# Run with custom paths
.\Sync-EnrollmentGroups.ps1 `
    -InputCSVPath "D:\Data\input\CourseEnrollmentData_2026-01-14.csv" `
    -AccessMappingPath "D:\Data\input\AccessMappings.csv" `
    -OutputDirectory "D:\Data\output" `
    -TargetOU "OU=CourseGroups,OU=Students,DC=example,DC=edu"
```

## Directory Structure

```
EnrollmentSync/
├── input/
│   ├── CourseEnrollmentData_2026-01-14.csv   # Dated enrollment data
│   └── AccessMappings.csv                     # Physical access rules
├── output/
│   ├── ClearanceUpload_2026-01-14.csv        # Physical access output
│   └── ADGroupMembership_2026-01-14.json     # WhatIf mode: proposed changes
└── Logs/
    └── sync-errors.log                        # Error log (only if errors occur)
```

## Date Handling

Output filenames are automatically dated:
- If the input filename contains a date (e.g., `CourseEnrollmentData_2026-01-14.csv`), that date is used
- Otherwise, the current date is used

This allows you to maintain historical output files and correlate them with their source data.

## How It Works

### Hierarchical Group Matching

If a student is enrolled in **MATH 101 Section 001**, they are automatically added to all matching groups:

| Group Level | Example Group Name | Matched? |
|-------------|-------------------|----------|
| Subject | "Student Enrolled in MATH" | Yes |
| Course | "Student Enrolled in MATH 101" | Yes |
| Section | "Student Enrolled in MATH 101 Section 001" | Yes |

### Physical Access Mapping

Access clearances can be assigned at any level:

```csv
SUBJECTCODE,COURSENUMBER,SECTIONNUMBER,CLEARANCE
CHEM,,,CHEM_BUILDING          # All CHEM students
CHEM,210,,CHEM_LAB_GENERAL    # All CHEM 210 students
CHEM,310,001,CHEM_HAZMAT      # Only CHEM 310 Section 001
```

### WhatIf Mode

Running with `-WhatIf` generates a JSON report showing all proposed changes without making them:

```powershell
.\Sync-EnrollmentGroups.ps1 -InputCSVPath ".\input\CourseEnrollmentData_2026-01-14.csv" -WhatIf
# Outputs: output/ADGroupMembership_2026-01-14.json
```

The JSON includes:
- Metadata (source file, timestamp, target OU)
- Per-group details (current members, proposed members, adds, removes)
- Summary totals

## Sample Data

The [samples/](samples/) directory contains example files:

**Input:**
- [input/CourseEnrollmentData_2026-01-14.csv](samples/input/CourseEnrollmentData_2026-01-14.csv) - Enrollment data
- [input/AccessMappings.csv](samples/input/AccessMappings.csv) - Physical access rules

**Output:**
- [output/ClearanceUpload_2026-01-14.csv](samples/output/ClearanceUpload_2026-01-14.csv) - Physical access file
- [output/ADGroupMembership_2026-01-14.json](samples/output/ADGroupMembership_2026-01-14.json) - WhatIf JSON report

## Custom Group Naming

Group name patterns are configurable via regex with named capture groups:

```powershell
.\Sync-EnrollmentGroups.ps1 `
    -SubjectGroupPattern '^Enrolled - (?<Subject>[A-Z]+)$' `
    -CourseGroupPattern '^Enrolled - (?<Subject>[A-Z]+) (?<Course>\S+)$' `
    -SectionGroupPattern '^Enrolled - (?<Subject>[A-Z]+) (?<Course>\S+) - (?<Section>.+)$'
```

## Documentation

- [TECHNICAL_REFERENCE.md](TECHNICAL_REFERENCE.md) - Input/output formats, processing flow, configuration
- [PROJECT_SUMMARY.md](PROJECT_SUMMARY.md) - Business case, benefits, compliance considerations

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Active Directory PowerShell module
- Appropriate AD permissions for group membership management

## License

MIT License - See [LICENSE](LICENSE) for details.

## Author

Andrew Marx (andrew@xram.net)
