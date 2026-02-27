This project's repository is organized as follows:

```
Root
│   README.md          # Project description
│   Repo_Structure.md  # This file
│
├───Prompts
│   │   <Application Name>.md   # Markdown prompt
│   |   <Application Name>.html # HTML prompt (Utilized version)
│
├───Code
│   │
│   ├───<LLM Developer>
│   │   |
|   |   |   <Application Name>.sol   # Code as the LLM generated
|   |   |   <Application Name>_C.sol # Compilation errors solved
|   |   |   <Application Name>_F.sol # Libraries flattened
│   |
|   |  ... 
|
├───Reports
│   │
│   ├───<LLM Developer>
│   │   |
|   |   ├───<Application>
|   |   |   |
|   |   |   ├───<Analyzer>
|   |   |   |   |
|   |   |   |   |   result.sarif # Analyzer report
|   |   |   |   |   ...          # Related log files
|   |   |   |
|   |   |   |   ...
|   |   |   |
|   |   |   └───EMPTY # Tools that returned empty reports
|   |   |
|   |   |   ...
|   |   |
|   |   |   <file>.csv   # Compilation of all reports
|   |
|   |   <file>.py                 # Scripts used to analyze 
|   |                               results
|   |   Vulnerability_groups.json # Vulnerabilities of different 
|   |                               analyzers grouped together
|   |   complete_report.json      # Compilation of vulnerability 
|                                   count
|
└───More_Information
    |   ... # Additional project details and results
```