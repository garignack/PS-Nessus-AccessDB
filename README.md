PS-Nessus-AccessDB
==================

This application parses a NessusV2 file into an Access Database for analysis and reporting.

Usage
==================

1. Place All PSNessusDB folder into one of your module directories: 
     - <UserDirectory>\Documents\WindowsPowerShell\Modules
	 - <WindowsDir>\System32\WindowsPowerShell\v1.0\Modules
   The PowerShell module paths are listed in the $Env:PSModulePath environment variable.
   
2. Download the NATemplate.accdb file rename it.  This will be where the results are stored. 
3. Open Powershell, import the PSNessusDB module and create variables to your files 

   PS> Import-Module PSNessusDB

   PS> $dir = "c:\path\to\nessusfiles" 
			---- or ---- 
   PS> $file = "c:\path\to\file.nessus"

   PS> $db = "c:\path\to\db.accdb" (saved in Step 2)

5. Run the applicable script to import Nessus results into a powershell database
  a. Single File: PS> Import-PSNessusDB $file $db 
  b. Directory (recursive): PS c:\ps-nessus-accdb> . .\process-directory.ps1 "c:\path\to\files" "c:\path\to\db.accdb"


Database Schema
==================

Files - Nessus File information
Hosts - Host Information
PluginInfo - Plugin Information that does not change between findings
ReportItem - Specfic finding information per host.