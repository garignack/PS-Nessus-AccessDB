Param(
   [Parameter(Mandatory=$True, HelpMessage="The Directory of Nessus Files to Process")]
   [Alias("f")]
   [ValidateScript({Test-Path $_ })]
   [string]$fileIN,
   
   [Parameter(Mandatory=$True, HelpMessage="The AccessDB to import results to")]
   [Alias("d")]
   [ValidateScript({Test-Path $_ })]
   [string]$AccessDB,
  
   [Alias("p")]
   [ValidateRange(1,99)] 
   [int]$maxPool = '1'
   
)

#---- Imports ----
$scriptPath = split-path $MyInvocation.MyCommand.Path
import-Module "$scriptPath\AccessDBFunctions.ps1"

#---- Variables ----
[int]$intHostsRead = 0
[int]$intHostsProcessed = 0
$fileIn = resolve-path $fileIn
$AccessDB = resolve-path $AccessDB
$psfile = resolve-path "$scriptPath\add-NessusHost.ps1"

#---- Start of Script ----
# Build a new Stream Reader and capture the file length
$sr = new-object system.io.streamreader $fileIN, 4096
$srLEN = $sr.BaseStream.Length

# Check to ensure this is a correct Nessus_V2 file
[void] $sr.ReadLine()
if($($sr.ReadLine()).contains("<NessusClientData_v2>") -ne $true) {
    Throw "$($fileIN) is not a valid Nessus_V2 file"
}

# Check if the file has been processed already
$conn = New-Object System.Data.OleDb.OleDbConnection("Provider=Microsoft.ACE.OLEDB.12.0; Data Source=$AccessDB") 
$conn.Open() 

$result = Get-AccessData "SELECT ID,ImportDate  from FILES where FileLoc = '$fileIN'" $conn
if ($result) { 
    Write-Warning "File Already Processed on: $result.ImportDate"
    if ($(Read-Host "Continue Y/N") -ne "Y") {
        Throw ("File Already Processed")
    }
}



# Record the file being processed and receive the $fileID variable
$sqlParam = @()
$sqlValue = @()

#Find the Report Name
$reportName = $null
while ($reportName -eq $null) {
    $line = $sr.ReadLine()
    if ($line.startswith('<Report '))
    {
        $a = $line.indexof("name=") + 6
        $b = $line.indexof(" xmlns:")
        $reportName = $line.substring($a, $b - $a - 1 )
    }
}

#fill File Entry parameters
$sqlParam += "reportName"
$sqlValue += $reportName
$sqlParam += "FileLoc"
$sqlValue += $fileIN
$sqlParam += "FileName"
$sqlValue += $(split-path $fileIN -leaf -resolve)
$sqlParam += "ImportDate"
$sqlValue += get-date


$fileID = add-AccessData "Files" $sqlParam $sqlValue $conn

#MultiThreading Setup
if ($maxPool -gt 1)  {
    $i = 0
    
    #Arrays
    
    $jobs = New-Object System.Collections.ArrayList  
    $ps = New-Object System.Collections.ArrayList   
    $wait = New-Object System.Collections.ArrayList
    $mtHosts = New-Object System.Collections.ArrayList
     
    # Import Processing function 
    $ScriptBlock = `
        {
            Param($psFile, $xmlHost, $accessDB, $fileID)
            & $psFile $xmlHost $accessDB $fileID
        }
    
    # MultiThreading: Create a pool of 3 runspaces 
    $pool = [runspacefactory]::CreateRunspacePool(1, $maxPool)   
    $pool.ApartmentState = "MTA"
    $pool.ThreadOptions = "ReuseThread"
	$pool.Open()
    write-host "Available Runspaces: $($pool.GetAvailableRunspaces())" 
    
}

#Begin Reading the file
while (($line = $sr.ReadLine()) -ne $null) 
   {
     
   #If the line contains <ReportHost, Capture the host entry into a Object and start a processing thread 
   if ($line.contains("<ReportHost") -eq $true){
        # Add the <ReportHost Line 
        $strBuffer = $line
        
        # Add the rest of the ReportHost lines, stoppping on </ReportHost>.
        
        while ($line.StartsWith("</ReportHost") -ne $true){
            $line = $sr.ReadLine()
            $strBuffer += $line
        }
        
        #convert the ReportHost string into an XML object
        [xml]$xmlHost = $strBuffer
        $intHostsRead++
        # Process the host XML object
        
        if ($maxPool -lt 2)  {
        # Single Threaded Processing
            write-Host "Processing: $($xmlhost.ReportHost.name)"
            & $psfile $xmlhost $accessDB $fileID
            
            $intHostsProcessed++
            
        } else {
        #MultiThreaded Processing    
        
        # Have the Pool queue a grow no more than double the number of threads.        
        write-Host "Processing: $($xmlhost.ReportHost.name)"
        $mtHosts.insert(0, $($xmlhost.ReportHost.name))
                
        #Add a new PS process to the $PS array and assign it to use the runspace pool
        $ps.insert(0, $([powershell]::create())) 
        $ps[0].runspacepool = $pool
            
        #Setup PS process to process the $xmlHost object 
        [void]$ps[0].AddScript($ScriptBlock).addargument($($psFile)).addargument($xmlhost).addargument($(resolve-path $accessDB)).addargument($fileID)               
                
        #Start a processing thread
        $jobs.insert(0, $($ps[0].BeginInvoke()))
                
          #Capture the wait handle
          $wait.insert(0, $($jobs[0].AsyncWaitHandle))
          $i++
                
          if (($wait.count % ($maxPool * 2)) -eq 0){
               Write-Host "---- Checking Processing Status of $($wait.count) processes ----"
              $success = [System.Threading.WaitHandle]::WaitAny($wait)
                for ($j = 0; $j -lt $wait.count; $j++) {
                    switch ($ps[$j].InvocationStateInfo.state){
                        "Running" {}
                        "Completed" {
                            write-host "++ $($mthosts[$j]) processed successfully"
                            $ps[$j].EndInvoke($jobs[$j])
                            $ps[$j].dispose()
                            $ps.removeAt($j)
                            $jobs.removeAt($j)
                            $wait.removeAt($j)
                            $mtHosts.removeAt($j)
                            $i--
                            $intHostsProcessed++
                        }
                        "Failed" {
                            write-host "-- $($mthosts[$j]) failed; Reason: $($ps[$j].InvocationStateInfo.Reason)"
                            $ps[$j].EndInvoke($jobs[$j])
                            $ps[$j].dispose()
                            $ps.removeAt($j)
                            $jobs.removeAt($j)
                            $wait.removeAt($j)
                            $mtHosts.removeAt($j)
                            $i--
                            $intHostsProcessed++
                        }                    

                    } # switch
                    
                } # For Loop
            } # MT Capture Results statement
         } # MT If Statement
   $strBuffer = $null
   $xmlHost = $null
         
   } # If <ReportHost> statement
   
   $srPOS = $sr.BaseStream.Position  
   Write-Progress -activity "Processing $($fileIN)" -status "File Read: $($srPOS) / $($srLEN); Hosts: Processed/Read $($intHostsProcessed) / $($intHostsRead)" -percentComplete (($sr.BaseStream.Position / $srLEN)  * 100)
   
   } # Processing While Loop 
 
 if ($maxpool -gt 1){
 
 #Finish
 while ($wait.count -ne 0){
 
while ($wait.count -gt 0){

Write-Progress -activity "Finishing..." -status "Hosts: Processed/Read $($intHostsProcessed) / $($intHostsRead)" -percentComplete  (($intHostsProcessed / $intHostsRead) * 100)

 for ($j = 0; $j -lt $wait.count; $j++) {
   switch ($ps[$j].InvocationStateInfo.state){
     "Running" {}
     "Completed" {
         write-host "++ $($mthosts[$j]) processed successfully"
         $ps[$j].EndInvoke($jobs[$j])
         $ps[$j].dispose()
         $ps.removeAt($j)
         $jobs.removeAt($j)
         $wait.removeAt($j)
         $mtHosts.removeAt($j)
         $i--
         $intHostsProcessed++
       }
       "Failed" {
            write-host "$($mthosts[$j]) failed; Reason: $($ps[$j].InvocationStateInfo.Reason)"
            $ps[$j].EndInvoke($jobs[$j])
            $ps[$j].dispose()
            $ps.removeAt($j)
            $jobs.removeAt($j)
            $wait.removeAt($j)
            $mtHosts.removeAt($j)
            $i--
            $intHostsProcessed++
        } 
    } #switch
}# for

}

}# while
$pool.close()
$pool = $null
}
#cleanup

$conn.close()
$conn = $null
