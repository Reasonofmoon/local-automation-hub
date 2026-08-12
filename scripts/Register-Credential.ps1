[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^LocalAutomationHub/Kakao/[A-Za-z0-9][A-Za-z0-9._-]{0,63}$')]
    [string]$TargetName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class CredentialNative {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct CREDENTIAL {
        public UInt32 Flags;
        public UInt32 Type;
        public string TargetName;
        public string Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public UInt32 CredentialBlobSize;
        public IntPtr CredentialBlob;
        public UInt32 Persist;
        public UInt32 AttributeCount;
        public IntPtr Attributes;
        public string TargetAlias;
        public string UserName;
    }

    [DllImport("Advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool CredWrite(ref CREDENTIAL credential, UInt32 flags);
}
'@

$secureValue = Read-Host -Prompt 'Credential value' -AsSecureString
$unmanagedValue = [IntPtr]::Zero
try {
    $unmanagedValue = [Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($secureValue)
    $credential = [CredentialNative+CREDENTIAL]@{
        Flags = 0
        Type = 1
        TargetName = $TargetName
        Comment = $null
        CredentialBlobSize = [uint32]($secureValue.Length * 2)
        CredentialBlob = $unmanagedValue
        Persist = 2
        AttributeCount = 0
        Attributes = [IntPtr]::Zero
        TargetAlias = $null
        UserName = $TargetName
    }
    if (-not [CredentialNative]::CredWrite([ref]$credential, 0)) {
        $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "CredWriteW failed with Win32 error $code."
    }
    Write-Host "Credential registered for target: $TargetName"
} finally {
    if ($unmanagedValue -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeCoTaskMemUnicode($unmanagedValue)
    }
    $secureValue.Dispose()
}
