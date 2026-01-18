# Automation in Academia

A collection of scripts for common IT automation tasks in academic environments. If you have a similar need, I hope they're useful to you as well.

## PowerShell

| Script | Description |
|--------|-------------|
| [EnrollmentSync](Powershell/EnrollmentSync/) | Syncs enrollment data to Active Directory groups and generates physical access control files. Supports hierarchical group matching, configurable naming patterns, and WhatIf mode with JSON export. |
| [FOCUSExport-AzureLocal](Powershell/FOCUSExport-AzureLocal/) | Exports FOCUS-format billing data from Azure Local (Azure Stack HCI) VMs. Supports tier-based pricing, proration, subsidies, and configurable audit output (Text/Json/Splunk). |

## Bash

| Script | Description |
|--------|-------------|
| [FOCUSExport-Slurm](Bash/FOCUSExport-Slurm/) | Exports FOCUS-format billing data from Slurm HPC accounting. Supports SU-based pricing with partition multipliers, free-tier subsidies, and WhatIf mode. |
| [FOCUSExport-Isilon](Bash/FOCUSExport-Isilon/) | Exports FOCUS-format billing data from Isilon storage quotas. Supports per-TB pricing with configurable free tier (e.g., first 500GB free). |

## License

All scripts are released under the MIT License unless otherwise noted. See individual script folders for details.

## Author

Andrew Marx (andrew@xram.net)
