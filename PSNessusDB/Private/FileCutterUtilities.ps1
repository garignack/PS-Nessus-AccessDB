#######################################################################################################################
# File:             Private/FileCutterUtilities.ps1
# Description:      Provides C#-backed file slicing utilities for extracting byte and string ranges from large Nessus
#                   exports, including search helpers used to identify ReportHost boundaries.
# Context:          Shared between import pipelines; depends on the embedded PSNessusDB.Cutter class. Extend encoding
#                   support here when new formats appear to keep Import-PSNessusDB lean.
#######################################################################################################################

function Initialize-FileCutter {
    if ("PSNessusDB.Cutter" -as [Type]) {
        return
    }

    $source = @"
using System;
using System.IO;
using System.Collections.Generic;

namespace PSNessusDB
{
    public class Cutter
    {
        public static List<int> SearchBytePattern(byte[] pattern, string fileName)
        {
            int bufferSize = 65536;
            byte[] needle = pattern;
            if (needle.Length > bufferSize)
            {
                bufferSize = needle.Length * 2;
            }
            byte[] haystack = new byte[bufferSize];

            List<int> matches = new List<int>();
            using (FileStream stream = new FileStream(fileName, FileMode.Open, FileAccess.Read))
            {
                int bytesToRead = (int)stream.Length;
                if (needle.Length > bytesToRead)
                {
                    return matches;
                }
                int[] badShift = BuildBadCharTable(needle);

                while (bytesToRead > 0)
                {
                    int position = (int)stream.Position;
                    int readCount = stream.Read(haystack, 0, bufferSize);
                    if (readCount == 0)
                    {
                        break;
                    }
                    while (needle.Length > readCount)
                    {
                        byte[] buffer = new byte[bufferSize - readCount];
                        int overflow = stream.Read(buffer, 0, buffer.Length);
                        if (overflow == 0)
                        {
                            break;
                        }
                        Array.Copy(haystack, 0, buffer, readCount, readCount);
                        readCount += overflow;
                    }
                    bytesToRead -= readCount;
                    int offset = 0;
                    int scan = 0;
                    int last = needle.Length - 1;
                    int maxOffset = haystack.Length - needle.Length;
                    while (offset <= maxOffset)
                    {
                        for (scan = last; (needle[scan] == haystack[scan + offset]); scan--)
                        {
                            if (scan == 0)
                            {
                                int match = position + offset;
                                matches.Add(match);
                                offset++;
                                break;
                            }
                        }
                        if (offset + last > haystack.Length - 1)
                        {
                            break;
                        }
                        offset += badShift[(int)haystack[offset + last]];
                    }
                    long newPosition = position + readCount - needle.Length;
                    stream.Position = newPosition < 0 ? 0 : newPosition;
                }
            }
            return matches;
        }

        private static int[] BuildBadCharTable(byte[] needle)
        {
            int[] badShift = new int[256];
            for (int index = 0; index < 256; index++)
            {
                badShift[index] = needle.Length;
            }
            int last = needle.Length - 1;
            for (int index = 0; index < last; index++)
            {
                badShift[(int)needle[index]] = last - index;
            }
            return badShift;
        }

        public static byte[] GrabBytes(string fileName, int start, int finish)
        {
            byte[] buffer;
            using (FileStream stream = new FileStream(fileName, FileMode.Open, FileAccess.Read))
            {
                int maxSize = (int)stream.Length;
                if (finish == -1 || finish > maxSize)
                {
                    finish = maxSize;
                }
                if (start < 0)
                {
                    start = 0;
                }

                int length = finish - start;
                buffer = new byte[length];
                stream.Seek(start, SeekOrigin.Begin);
                stream.Read(buffer, 0, length);
            }
            return buffer;
        }
    }
}
"@

    Add-Type -TypeDefinition $source -Language CSharp
}

function Resolve-TextEncoding {
    param(
        [Parameter(Mandatory)]
        [object]$Name
    )

    if ($Name -is [System.Text.Encoding]) {
        return $Name
    }

    if (-not $Name) {
        throw "Encoding name cannot be empty."
    }

    $value = $Name.ToString()

    switch ($value.ToUpperInvariant()) {
        'DEFAULT' { return [System.Text.Encoding]::Default }
        'UTF7' { return [System.Text.Encoding]::UTF7 }
        'UTF8' { return [System.Text.Encoding]::UTF8 }
        'UTF32' { return [System.Text.Encoding]::UTF32 }
        'UNICODE' { return [System.Text.Encoding]::Unicode }
        'ASCII' { return [System.Text.Encoding]::ASCII }
        default { throw "Unsupported encoding '$value'." }
    }
}

function Get-ByteMatchLocations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Alias('f')]
        [ValidateScript({ Test-Path $_ })]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [Alias('s')]
        [string]$Pattern,

        [string]$Encoding = 'DEFAULT'
    )

    Initialize-FileCutter
    $inputType = if ($null -eq $Encoding) { '<null>' } else { $Encoding.GetType().FullName }
    Write-Verbose ("[Get-ByteMatchLocations] Encoding input type: {0}; value: {1}" -f $inputType, $Encoding)
    $resolvedEncoding = Resolve-TextEncoding -Name $Encoding
    if ($resolvedEncoding -is [string]) {
        $encodingString = $resolvedEncoding.ToString()
        if ($encodingString -like 'System.Text.*') {
            $resolvedEncoding = [System.Text.Encoding]::Default
        }
        else {
            $resolvedEncoding = Resolve-TextEncoding -Name $encodingString
        }
    }

    if ($null -eq $resolvedEncoding -or $resolvedEncoding -isnot [System.Text.Encoding]) {
        $typeName = if ($null -eq $resolvedEncoding) { '<null>' } else { $resolvedEncoding.GetType().FullName }
        $value = if ($null -eq $resolvedEncoding) { '<null>' } else { $resolvedEncoding }
        throw "Resolved encoding is invalid (type: $typeName, value: $value)."
    }

    [byte[]]$bytes = $resolvedEncoding.GetBytes($Pattern)

    [array][PSNessusDB.Cutter]::SearchBytePattern($bytes, $FilePath)
}

function Get-FileBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Alias('f')]
        [ValidateScript({ Test-Path $_ })]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [int]$Start,

        [Parameter(Mandatory)]
        [int]$End
    )

    Initialize-FileCutter
    [byte[]][PSNessusDB.Cutter]::GrabBytes($FilePath, $Start, $End)
}

function Get-FileString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Alias('f')]
        [ValidateScript({ Test-Path $_ })]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [int]$Start,

        [Parameter(Mandatory)]
        [int]$End,

        [string]$Encoding = 'UTF8'
    )

    Initialize-FileCutter
    $resolvedEncoding = Resolve-TextEncoding -Name $Encoding
    if ($resolvedEncoding -is [string]) {
        $encodingString = $resolvedEncoding.ToString()
        if ($encodingString -like 'System.Text.*') {
            $resolvedEncoding = [System.Text.Encoding]::Default
        }
        else {
            $resolvedEncoding = Resolve-TextEncoding -Name $encodingString
        }
    }
    $bytes = [PSNessusDB.Cutter]::GrabBytes($FilePath, $Start, $End)
    $resolvedEncoding.GetString($bytes)
}

function Convert-BytesToString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias('b')]
        [byte[]]$Bytes,

        [string]$Encoding = 'ASCII'
    )

    begin {
        $script:ConvertBytesEncoding = Resolve-TextEncoding -Name $Encoding
        if ($script:ConvertBytesEncoding -is [string]) {
            $encodingString = $script:ConvertBytesEncoding.ToString()
            if ($encodingString -like 'System.Text.*') {
                $script:ConvertBytesEncoding = [System.Text.Encoding]::Default
            }
            else {
                $script:ConvertBytesEncoding = Resolve-TextEncoding -Name $encodingString
            }
        }
    }

    process {
        $script:ConvertBytesEncoding.GetString($Bytes)
    }

    end {
        Remove-Variable -Name ConvertBytesEncoding -Scope Script -ErrorAction SilentlyContinue
    }
}

Initialize-FileCutter
