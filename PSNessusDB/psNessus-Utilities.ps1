function Load-FileCutter {
$Source = @" 
using System;
using System.IO;
using System.Collections.Generic;

namespace PSNessusDB
{ 
    public class Cutter 
    { 
		public static List<int> SearchBytePattern(byte[] pattern, string FILE_NAME)
        {
			List<int> matches = new List<int>();
		    using (FileStream r = new FileStream(FILE_NAME, FileMode.Open, FileAccess.Read))
			{
					// precomputing this shaves some seconds from the loop execution
					int maxloop = (int)r.Length - (int)pattern.Length;
					for (int i = 0; i < maxloop; i++)
					{
						if (pattern[0] == r.ReadByte())
						{
							bool ismatch = true;
							for (int j = 1; j < pattern.Length; j++)
							{
								if (r.ReadByte() != pattern[j])
								{
									ismatch = false;
									r.Position = i + 1 ;
									break;
								}
							}
							if (ismatch)
							{
								matches.Add(i);
								i += pattern.Length - 1;
							}
						}
					}
			}
            return matches;
        }
		public static byte[] GrabBytes(string FILE_NAME, int locStart, int locEnd)
        {
			byte[] buffer;
		    using (FileStream r = new FileStream(FILE_NAME, FileMode.Open, FileAccess.Read))
			{
					int maxSize = (int)r.Length;
					if (locEnd == -1 || locEnd > maxSize ){locEnd = maxSize;}
					if (locStart < 0) {locStart = 0;}
			
			int length = locEnd - locStart;
			buffer = new byte[length];
			r.Seek(locStart, SeekOrigin.Begin);
			r.Read(buffer, 0, length);
            }			
			return buffer;
			
        }
    } 
} 
"@ 
	Add-Type -TypeDefinition $Source -Language CSharp
}

function Get-ByteMatchLocations{
	param(
		[Parameter(Mandatory=$True, HelpMessage="The File to Process")]
		[Alias("f")]
		[ValidateScript({Test-Path $_ })]
		[string]$fileIN,
		[Parameter(Mandatory=$True, HelpMessage="The String to Search For")]
		[Alias("s")]
		[string]$someString,
		[ValidateSet("UTF7","UTF8","UTF32","UNICODE","ASCII", "DEFAULT")] 
        [String]
        $Encoding = "DEFAULT"
	)	
	if($someString){ 
		$enc = [system.Text.Encoding]::$Encoding
		[byte[]] $bytes  = $enc.GetBytes($someString)
	}
	[array] $list = [PSNessusDB.Cutter]::SearchBytePattern($bytes, $fileIN)
	return $list
}
function Get-FileBytes{
	param(
		[Parameter(Mandatory=$True, HelpMessage="The File to Process")]
		[Alias("f")]
		[ValidateScript({Test-Path $_ })]
		[string]$fileIN,
		[Parameter(Mandatory=$True, HelpMessage="The Starting Byte Location")]
		[int]$startloc,
		[Parameter(Mandatory=$True, HelpMessage="The Ending Byte Location")]
		[int]$endloc
	)
	[byte[]] $bytes = [PSNessusDB.Cutter]::GrabBytes($fileIN, $startloc, $endloc)
	return $bytes
}

function Convert-BytesToString{
	[CmdletBinding()] param(
		[Parameter(ValueFromPipeline = $True, Mandatory=$True, HelpMessage="Bytes to Convert")]
		[Alias("b")]
		[Byte[]] $bytes,
		
		[ValidateSet("UTF7","UTF8","UTF32","UNICODE","ASCII", "DEFAULT")] 
        [String]
        $Encoding = "ASCII"
	)
	begin{$enc = [System.Text.Encoding]::$Encoding}
	process{return $enc.GetString($bytes)}
	end{}
}
