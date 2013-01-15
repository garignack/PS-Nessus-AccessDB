PS-Nessus-AccessDB
==================

This application parses a NessusV2 file into an Access Database for analysis and reporting.

Usage
==================

1. Place all files in a common folder
2. Copy the NATemplate.accdb file to create a a new desitination file
3. Open Powershell and navigate to the folder containing the scripts (Step 1)
4. Run the applicable script to import Nessus results into a powershell database
  a. Single File: PS c:\ps-nessus-accdb>  . .\nessus-accdb.ps1 "c:\path\to\file.nessus"  "c:\path\to\db.accdb" 
  b. Directory (recursive): PS c:\ps-nessus-accdb> . .\process-directory.ps1 "c:\path\to\files" "c:\path\to\db.accdb"

5. The "-p #" parameter will enable multi-threading.  This has the potential to increase processing speed.


Database Schema
==================

Files - Nessus File information
Hosts - Host Information
PluginInfo - Plugin Information that does not change between findings
ReportItem - Specfic finding information per host.

Coming Soon
==================
1. Reporting Tool
2. Auto create new database
3. Updated DB schema to more closely align with other Nessus Parsers. (Policy Information, References Table)
