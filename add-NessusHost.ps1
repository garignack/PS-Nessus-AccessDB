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
$sqlParam += $xmlhost.ReportHost.HostProperties.tag | foreach{$_.name}

$sqlValue += $fileID
$sqlValue += $xmlhost.ReportHost.name
$sqlValue += $xmlhost.ReportHost.HostProperties.tag | foreach{$_.'#text'}

fix-SQLColumns "Hosts" $sqlParam $conn

$hostID = add-AccessData "Hosts" $sqlParam $sqlValue $conn

#Process Report Items into Database
foreach($reportItem in $xmlhost.ReportHost.ReportItem)
{
    $sqlRParam = @()
    $sqlRValue = @()
    $sqlPParam = @()
    $sqlPValue = @()
    
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
                 default  {  
                    if ($sqlPParam -notcontains $a.name){
                        $sqlPParam += $a.name; $sqlPValue += $(get-SQLEscaping $a.'#text')
                    } else {
                        for ($k=0; $k -lt $sqlPParam.count; $k++){
                            if($sqlPParam[$k] -eq $a.name){$sqlPValue[$k] += "`r$(get-SQLEscaping $a.'#text')"}
                        }
                    }
                 }
            }   
     }
     
     #Calculate Plugin Hash.  Should match built-in parser
     
     $strHash = ""
     $strHash += $($reportItem.attributes | where-object {$_.name -eq "pluginID"}).'#text'
     $strHash += $($reportItem.childnodes | where-object {$_.name -eq "description"}).'#text'
     $strHash += $($reportItem.childnodes | where-object {$_.name -eq "plugin_version"}).'#text'
     $strHash += $($reportItem.attributes | where-object {$_.name -eq "pluginName"}).'#text'
     $strHash += $($reportItem.childnodes | where-object {$_.name -eq "plugin_publication_date"}).'#text'
     $hash = get-MD5Hash $strHash
     $sqlPParam += "PluginHash"
     $sqlPValue += $hash
     
     # Check to see if the Plugin is in the database.  If not: add it.
     $results = Get-AccessData "Select ID, PluginHash FROM PluginInfo WHERE PluginHash = '$hash';" $conn
     if ($results.Pluginhash -ne $hash){
        fix-SQLColumns "PluginInfo" $sqlPParam $conn
        $pluginID = add-AccessData "PluginInfo" $sqlPParam $sqlPValue $conn
     } else {
        $pluginID = $results.ID
     }
     
     # Add a Report item with the HostID and Plugin ID
     $sqlRParam += "HostID"
     $sqlRValue += $hostID
     
     $sqlRParam += "PID"
     $sqlRValue += $pluginID
     
     $reportID = add-AccessData "ReportItem" $sqlRParam $sqlRValue $conn
     
}
 
 #clean-up
 $conn.Close()
 $cmd = $null
 $conn = $null
 
 