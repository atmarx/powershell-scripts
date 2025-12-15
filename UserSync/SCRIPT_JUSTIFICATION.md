# Course Enrollment Synchronization: Project Justification

## Executive Summary
This initiative centralizes course-based Active Directory group management and introduces automated physical access provisioning across all colleges. By automating a critical but repetitive task currently handled inconsistently by ~12 distributed IT groups, we improve student experience, reduce support burden, and establish operational standards.

---

## 1. The Problem

**Current State:**
Distributed IT groups across our dozen colleges independently manage Active Directory security groups for course enrollments. Each college uses different methods:
- Most perform manual data exports and run scripts on an ad-hoc basis
- One group has fragile automation
- Each college uses its own naming convention for security groups
- Zero automation exists for physical access (card swipe) provisioning

**Pain Points:**
- **Time-Critical Manual Work**: Groups must remember to update memberships at key term dates. Forgetting creates immediate student impact.
- **Beginning-of-Term Crisis**: When updates are missed or delayed, students cannot access resources on day one, triggering avalanches of support tickets and walk-ins precisely when distributed IT is busiest.
- **Inconsistent Standards**: Varied naming conventions make centralized troubleshooting impossible. Central support must reassign tickets to colleges for investigation.
- **No Physical Access Integration**: Faculty in specialized facilities (labs, studios) must separately request building access for students, creating delays and manual coordination.
- **Resource Duplication**: Each sophisticated IT group independently maintains similar but incompatible solutions.

---

## 2. Who Benefits and How

### Distributed IT Groups (12 teams)
- **Eliminates repetitive work** during the busiest time of term (first week)
- **Removes responsibility** for remembering critical sync dates
- **Provides physical access automation** without additional effort
- **Standardizes approach** across all colleges for easier collaboration

### Students (~100,000 enrollments)
- **Day-one access** to learning management systems, file shares, and specialized software
- **Automatic building access** for labs and studios based on enrollment
- **Fewer access-related disruptions** to their first classes

### Faculty
- **Students arrive prepared** with working access from day one
- **Less time troubleshooting access issues** in first classes
- **Automatic physical access provisioning** for students in lab/studio courses

### Central IT - Accounts Team
- **Can now troubleshoot course group issues** without immediately escalating to colleges
- **Standardized naming convention** makes groups easy to identify
- **Built-in audit trail** via group descriptions showing last sync date, member counts, and changes
- **Owns group creation** using consistent standards, ensuring quality

### Central IT - Support Team
- **Reduced ticket reassignments** due to standardized naming and central visibility
- **Faster resolution** when students report access issues

### Systems Team
- **Standardized automation** simplifies AD management
- **Predictable nightly operation** replaces unpredictable distributed efforts
- **Clear ownership model** for ongoing maintenance

---

## 3. Work Completed to Date

### Requirements Gathering & Stakeholder Engagement
- **Multiple sessions with distributed IT groups** to understand current workflows, pain points, and requirements
- **Consultation with Data team** to confirm feasibility of nightly enrollment data exports from Student Information System (SIS)
- **Initial discussions with Systems team** confirming technical feasibility
- **Research into existing solutions** including examination of current bespoke scripts

### Design & Development
- **Script development** completed with comprehensive functionality:
  - Hierarchical group membership (subject → course → section levels)
  - Physical access clearance mapping and output generation
  - Extensive logging and audit trails (including group description updates)
  - WhatIf/testing mode support
  - Error handling and resilience
- **Documentation created**:
  - Technical overview for Data team collaboration
  - Pseudo-code workflow for non-technical stakeholders
  - This justification document

### Collaboration
- **Shared proof-of-concept via Azure DevOps** with distributed IT groups for review and feedback
- **Iterative refinement** based on stakeholder input

---

## 4. Remaining Work & Dependencies

### Systems Team (Critical Path)
- **AD Infrastructure Setup**:
  - Create dedicated OU for course enrollment groups
  - Verify/establish group naming convention: "Student Enrolled in {SUBJ}", "Student Enrolled in {SUBJ} {COURSE}", "Student Enrolled in {SUBJ} {COURSE} Section {SECTION}"
  - Create service account with appropriate permissions for group membership management
  - Identify Windows server VM for scheduled task execution

- **Automation & Version Control**:
  - Set up scheduled task for nightly execution
  - Create GitLab repository for production version (currently in Azure DevOps for distributed IT collaboration)
  - Establish change management process

### Data Team
- **Finalize data export details**:
  - Confirm nightly export schedule from SIS
  - Decide on monolithic vs. multiple export files
  - Establish file delivery mechanism and location
  - Confirm data quality and format

### Accounts Team
- **Process & Training**:
  - Document group request/creation workflow
  - Train on new naming conventions
  - Establish process for creating groups in correct OU
  - Define physical access clearance mapping governance (which courses get which building access)

### Testing & Rollout
- **Controlled Testing**:
  - Manual script execution with WhatIf mode
  - Validation with small subset of groups
  - Verify physical access output integrates with card access system

- **Phased Rollout**:
  - Script only processes groups that exist and match naming convention
  - Rollout speed controlled by Accounts team creating groups as requested
  - Low-risk gradual adoption allows colleges to opt-in at their pace

### Documentation & Communication
- **Distributed IT Communication**: Announce service, timeline, and transition plan
- **End-User Documentation**: Update knowledge base articles about course-based access

### Maintenance Model (To Be Determined)
- **Change Request Process**: How updates/enhancements are requested and prioritized
- **Ownership**: Proposed model - I maintain script in Azure DevOps, coordinate changes with Systems for production GitLab deployment
- **Monitoring**: Define success metrics and operational alerts

---

## 5. Benefits Summary & Strategic Value

### Operational Efficiency
- **~12 distributed IT groups** freed from repetitive, time-critical manual work
- **Centralized execution** replaces fragmented efforts across colleges
- **Estimated time savings**: Each group saves 2-4 hours per term (beginning, end, and schedule adjustments) = 24-48 staff hours per term across the university

### Service Quality
- **Zero-delay access** for students starting courses
- **Proactive automation** eliminates "forgetting" scenarios
- **Physical access integration** removes manual coordination steps

### Risk Reduction
- **Consistent execution** every night eliminates human error
- **Audit trail** via group descriptions provides transparency
- **Idempotent design** means safe to re-run without side effects
- **Controlled rollout** minimizes disruption risk

### Strategic Alignment
- **Standardization**: Establishes consistent practices across all colleges
- **Centralization**: Aligns with broader university IT consolidation goals
- **Scalability**: Solution handles current ~100,000 enrollments and scales with growth
- **Enhanced Support Model**: Enables central team to resolve issues previously requiring escalation

### Cost Avoidance
- **Prevents duplicate efforts**: Stops each college from independently maintaining similar solutions
- **Reduces support burden**: Fewer access-related tickets during critical beginning-of-term period
- **Avoids student impact costs**: Poor day-one experience affects retention and satisfaction

---

## Recommendation

**Proceed with implementation.** The technical solution is complete and proven. The primary remaining work involves operational setup (Systems team infrastructure) and coordination (Data team exports, Accounts team processes). The benefits significantly outweigh the implementation effort, and the phased rollout approach mitigates risk.

**Proposed Timeline:**
- **Weeks 1-2**: Systems team completes AD infrastructure and service account setup
- **Weeks 2-3**: Data team finalizes export process; Accounts team training
- **Week 4**: Initial testing with small group set
- **Week 5+**: Phased rollout controlled by group creation rate

This positions the solution for production use before the start of the next academic term, delivering immediate value when it matters most.
