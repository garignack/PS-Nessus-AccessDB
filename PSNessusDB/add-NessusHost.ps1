Param(
   [Parameter(Mandatory=$True)]
   [xml]$xmlHost,
	
   [Parameter(Mandatory=$True)]
   [string]$AccessDB,

   [Parameter(Mandatory=$True)]
   [int]$fileID
)
# [System.Reflection.Assembly]::LoadWithPartialName(“System.Windows.Forms”)
# [Windows.Forms.MessageBox]::Show(“Add-Host Ran”, “Debugging”, [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Information)

$scriptPath = split-path $MyInvocation.MyCommand.Path
import-Module "$scriptPath\AccessDBFunctions.ps1"

function get-MD5Hash ([string]$someString){
    $algo = [System.Security.Cryptography.HashAlgorithm]::Create("MD5")
    $md5StringBuilder = New-Object System.Text.StringBuilder
    $encoder = new-object -TypeName System.Text.UTF8Encoding
    $algo.ComputeHash($encoder.GetBytes($someString)) | % { [void] $md5StringBuilder.Append($_.ToString("x2")) }
    $md5StringBuilder.ToString() 
}

$conn = New-Object System.Data.OleDb.OleDbConnection("Provider=Microsoft.ACE.OLEDB.12.0; Data Source=$AccessDB") 
$conn.Open() 

#SQL commands
$sqlParam = @()
$sqlValue = @()

# Process Host Information
$sqlParam += "FileID"
$sqlParam += "Name"
$sqlValue += $fileID
$sqlValue += $xmlhost.ReportHost.name

foreach($tag in ($xmlhost.ReportHost.HostProperties.tag)){
    switch -wildcard ($tag.name){
        "netstat-*" {}
        "traceroute-*" {}
        "MS*" {}
        default {$sqlParam += $tag.name; $sqlValue += $(get-SQLEscaping $tag.'#text')}
    }
}

fix-SQLColumns "Hosts" $sqlParam $sqlValue $conn

$hostID = add-AccessData "Hosts" $sqlParam $sqlValue $conn

#Process Report Items into Database
foreach($reportItem in $xmlhost.ReportHost.ReportItem)
{
	$sqlRParam = @()
    $sqlRValue = @()
    $sqlPParam = @()
    $sqlPValue = @()
    
     #Calculate Plugin Hash.  Should match built-in parser
     
	 $strHash = ""
	 $strHash = $reportItem.PluginID + $reportItem.description + $reportItem.'plugin_version' + $reportItem.pluginName + $reportItem.'Plugin_Publication_Date'
	 
     $hash = get-MD5Hash $strHash
     $sqlPParam += "PluginHash"
     $sqlPValue += $hash
	 
     # Check to see if the Plugin is in the database.  If not: add it.
     $results = Get-AccessData "Select ID, PluginHash FROM PluginInfo WHERE PluginHash = '$hash';" $conn
	 
     if ($results.Pluginhash -ne $hash){
	     # Process attributes into Report Item and PluginItem arrays
	    foreach($a in ($reportItem.attributes))
	    {
	        switch -wildcard ($a.name) 
	            {
	                "plugin*" {$sqlPParam += $a.name; $sqlPValue += $(get-SQLEscaping $a.'#text')}
	                 default  {$sqlRParam += $a.name; $sqlRValue += $(get-SQLEscaping $a.'#text')}
	            }   
	    }
		# Process attributes into Report Item and PluginItem arrays 
	 	foreach($a in ($reportItem.childnodes))
	    {
	        switch -wildcard ($a.name) 
	            {
	                "plugin_output" { $sqlRParam += $a.name; $sqlRValue += $(get-SQLEscaping $a.'#text')}
					"cm:compliance-result" { $sqlRParam += $a.name; $sqlRValue += $(get-SQLEscaping $a.'#text')}
					"cm:compliance-actual-value" { $sqlRParam += $a.name; $sqlRValue += $(get-SQLEscaping $a.'#text')}
					
	                 default  {  
	                    if ($sqlPParam -notcontains $a.name){
	                        $sqlPParam += $a.name; $sqlPValue += $(get-SQLEscaping $a.'#text')
	                    } else {
	                        for ($k=0; $k -lt $sqlPParam.count; $k++){
	                            if($sqlPParam[$k] -eq $a.name){$sqlPValue[$k] += ";$(get-SQLEscaping $a.'#text')"}
	                        }
	                    }
	                 }
	            }   
	     }
	 	fix-SQLColumns "PluginInfo" $sqlPParam $sqlValue $conn
        $pluginID = add-AccessData "PluginInfo" $sqlPParam $sqlPValue $conn
		
     } else #Don't process all plugin information if a plugin already exists, only process what is needed for the ReportItem table.
	 {  
        $pluginID = $results.ID
		foreach($a in ($reportItem.attributes))
		{
        	switch -wildcard ($a.name) 
            {
                "plugin*" {}
                 default  {$sqlRParam += $a.name; $sqlRValue += $(get-SQLEscaping $a.'#text')}
            }   
    	}
		$sqlRParam += "plugin_output"; $sqlRValue += $(get-SQLEscaping $reportItem.plugin_output)
		if ($reportItem.'cm:compliance-result')
		{
			$sqlRParam += "cm:compliance-result"; $sqlRValue += $(get-SQLEscaping $reportItem.'cm:compliance-result')
		}
		if ($reportItem.'cm:compliance-actual-value')
		{
			$sqlRParam += "cm:compliance-actual-value"; $sqlRValue += $(get-SQLEscaping $reportItem.'cm:compliance-actual-value')
		}
     }
	 
     if($pluginID) {
	     # Add a Report item with the HostID and Plugin ID
	     $sqlRParam += "HostID"
	     $sqlRValue += $hostID
	     
	     $sqlRParam += "PID"
	     $sqlRValue += $pluginID
	     
	     $reportID = add-AccessData "ReportItem" $sqlRParam $sqlRValue $conn
     }
	 else
	 { 
	 	Write-Warning "Could not find Plugin: $($($reportItem.attributes | where-object {$_.name -eq "pluginID"}).'#text')"
	 }
}
 
 #clean-up
 $conn.Close()
 $cmd = $null
 $conn = $null
 