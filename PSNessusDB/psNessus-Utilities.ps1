function Load-FileCutter {
$Source = @" 
using System;
using System.IO;
using System.Collections.Generic;

namespace PSNessusDB
{ 
    public class Cutter 
    { 
		//Implements Boyd-Moyer-HorsePool Algorithm
		//Adapted from http://aspdotnetcodebook.blogspot.com/2013/04/boyer-moore-search-algorithm.html
		
		public static List<int> SearchBytePattern(byte[] pattern, string FILE_NAME)
        {
			int bufferSize = 65536;
            byte[] needle = pattern;
            if (needle.Length > bufferSize) {bufferSize = needle.Length * 2;}
            byte[] haystack = new byte[bufferSize];
            
            List<int> matches = new List<int>();
            using (FileStream fs = new FileStream(FILE_NAME, FileMode.Open, FileAccess.Read))
            {
                int numBytesToRead = (int)fs.Length;
                if (needle.Length > numBytesToRead)
                {
                        return matches;
                }
                int[] badShift = BuildBadCharTable(needle);

                while (numBytesToRead > 0)
                {
                    int pos = (int)fs.Position;
                    int n = fs.Read(haystack, 0, bufferSize);
                    if (n == 0) { break; }
                    while (needle.Length > n)
                    {
                        byte[] buffer = new byte[bufferSize - n];
                        int o = fs.Read(buffer, 0, buffer.Length);
                        if (o == 0) { break; }
                        haystack.CopyTo(buffer, n);
                        n = n + o;
                    }
                    numBytesToRead = numBytesToRead - n;
                    int offset = 0;
                    int scan = 0;
                    int last = needle.Length - 1;
                    int maxoffset = haystack.Length - needle.Length;
                    while (offset <= maxoffset)
                    {
                        for (scan = last; (needle[scan] == haystack[scan + offset]); scan--)
                        {
                            if (scan == 0)
                            { //Match found
                                int i = pos + offset;
                                matches.Add(i);
                                offset++;
                                break;
                            }
                        }
                        if (offset + last > haystack.Length - 1) { break; }
                        offset += badShift[(int)haystack[offset + last]];
                    }
                    fs.Position = pos + n - needle.Length;
                }
            }
            return matches;
        }
		
		private static int[] BuildBadCharTable(byte[] needle)
        {
            int[] badShift = new int[256];
            for (int i = 0; i < 256; i++)
            {
                badShift[i] = needle.Length;
            }
            int last = needle.Length - 1;
            for (int i = 0; i < last; i++)
            {
                badShift[(int)needle[i]] = last - i;
            }
            return badShift;
        }
		
		public static byte[] GrabBytes(string FILE_NAME, int locStart, int locEnd)
        {
			byte[] buffer;
		    using (FileStream fs = new FileStream(FILE_NAME, FileMode.Open, FileAccess.Read))
			{
					int maxSize = (int)fs.Length;
					if (locEnd == -1 || locEnd > maxSize ){locEnd = maxSize;}
					if (locStart < 0) {locStart = 0;}
			
			int length = locEnd - locStart;
			buffer = new byte[length];
			fs.Seek(locStart, SeekOrigin.Begin);
			fs.Read(buffer, 0, length);
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
function Get-FileString{
	[CmdletBinding()] param(
		[Parameter(Mandatory=$True, HelpMessage="The File to Process")]
		[Alias("f")]
		[ValidateScript({Test-Path $_ })]
		[string]$fileIN,
		[Parameter(Mandatory=$True, HelpMessage="The Starting Byte Location")]
		[int]$startloc,
		[Parameter(Mandatory=$True, HelpMessage="The Ending Byte Location")]
		[int]$endloc,
		[ValidateSet("UTF7","UTF8","UTF32","UNICODE","ASCII", "DEFAULT")] 
        [String]
        $Encoding = "UTF-8"
	)
	begin{$enc = [System.Text.Encoding]::$Encoding}
	process{
	[byte[]] $bytes = [PSNessusDB.Cutter]::GrabBytes($fileIN, $startloc, $endloc)
	return $enc.GetString($bytes)
	}
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

Load-FileCutter