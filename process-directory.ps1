Param(
   [Parameter(Mandatory=$True, HelpMessage="The Directory of Nessus Files to Process")]
   [ValidateScript({Test-Path $(resolve-path $_)})]
   [string] $path = ".",
   
   [Parameter(Mandatory=$True, HelpMessage="The AccessDB to import results to")]
   [ValidateScript({Test-Path $_ })]
   [string]$AccessDB,
   
   [Alias("p")]
   [ValidateRange(1,99)] 
   [int]$maxPool = '1'   
   )
   
$rpath = resolve-path $path
write-host "------------ Finding .Nessus Files --------------------"
$nessusFiles = get-childitem -d $rpath -include *.nessus -recurse -force
$nessusFiles
$scriptPath = split-path $MyInvocation.MyCommand.Path
$script = "$($scriptPath)\nessus-accdb.ps1"

ForEach ($file in $nessusFiles) {
    write-host "-------------------$($file.name)--------------------"
    & $script "$($file.fullname)" $accessDB $maxPool
    write-host "-------------------Complete--------------------"
}
