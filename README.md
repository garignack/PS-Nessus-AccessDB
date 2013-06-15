###PSNessusDB
### PSNessusDB is a Powershell and Microsoft Access toolkit for parsing and analyzing Tennable Nessus Scan results.  It was designed to aid information security professionals with processing and evaluting large, complex result sets with minimal installation requirements.  PSNessusDB is comprised of the following components: 

##Powershell Module
The PSNessusDB Powershell module is designed to quickly import Nessus results into an Microsoft 2007 Access backend database.  It works by anaylzing a Nessus_V2 file, locating all ReportHost entries.  It then extracts and parses each entry into the database.
  
##Usage
Intial Installation

1. Place the PSNessusDB folder into one of your module directories: 
     - <UserDirectory>\Documents\WindowsPowerShell\Modules
	 - <WindowsDir>\System32\WindowsPowerShell\v1.0\Modules
   The PowerShell module paths are listed in the $Env:PSModulePath environment variable.
    
2. Save the NATemplate.accdb file to a new name and location.  This will be where the database where the results are stored. 

3. Open Powershell, import the PSNessusDB module and create variables to your .nessus and .accdb files 

   PS> Import-Module PSNessusDB

    PS> $file = "c:\path\to\file.nessus"
			---- or ---- 
    PS> $dir = "c:\path\to\nessusfiles"

   PS> $db = "c:\path\to\db.accdb" (saved in Step 2)

5. Run the applicable script to import Nessus results into a powershell database
  a. Single File: PS> Import-PSNessusDB $file $db
  
  b. Directory (recursive): PS c:\ps-nessus-accdb> gci $dir -filter "*.nessus" | Import-PSNessusDB -d $db

##Database Schema
Files - Nessus File information
Hosts - Host Information
PluginInfo - Plugin Information that does not change between findings
ReportItem - Specfic finding information per host.

##Import-PSNessusDB Help Comments

	<# 
	.SYNOPSIS
		Imports a Nessus_V2 file into a Microsoft Access Database

	.DESCRIPTION
		A Powershell cmdlet that takes a Nessus_V2 file as an input and parses it into an Access Database. 
		Accepts $Fullname parameters from the pipeline for processing multiple files at once.
		Utilizes a multi-level logging module for configurable logging outputs
		Supports --debug and --verbose flags for additional information		

	.PARAMETER  FullName
		Alias: f or file
		Absolute or Relative path to Nessus File.  Accepts Pipeline Inputs
	
	.PARAMETER  AccessDB
		Alias: db
		Absolute or Relative path to PSNessusDB Access Database File
		
	.PARAMETER  LogFileName
		Alias: l
		Absolute or Relative path
		
	.PARAMETER  Trace
		Enables All Logging
		
	.PARAMETER NoLog 
		Disables all logging
		
	.EXAMPLE
		Single File Processing
		$file = "C:\Path\To\Scan.nessus"
		$db = "C:\Path\To\Scan.accdb"
		$LogFile = "C:\Path\To\scan.log"
		Import-PSNessusDB -f $File -db $db -l $log  

		Pipeline Processing
		$dir = "C:\Path\To"
		Get-ChildItem -d $dir -include *.nessus -recurse -force | Import-PSNessusDB -f $file -db $db -l $log
		
	.INPUTS
		Nessus_V2 File

	.OUTPUTS
		Microsoft Access Database

	.NOTES
		Credits:
		Joshua Poehls (Jpoehls): https://github.com/jpoehls/hulk-example/blob/master/_posts/2013/2013-01-24-benchmarking-with-Powershell.md
		Hemanth.D:  http://sqlchow.wordpress.com/2012/08/06/creating-a-logging-framework-in-powershell-the-final-part/ 
		SANTOSH: http://aspdotnetcodebook.blogspot.com/2013/04/boyer-moore-search-algorithm.html

	.LINK
		https://github.com/garignack/PS-Nessus-AccessDB
	#>