#Requires AutoHotkey v2.0

; CREDENTIALW uses pointer-aligned fields. CredentialBlobSize is at
; 16 + (2 * A_PtrSize), and CredentialBlob begins at the next pointer boundary.
class CredentialStore {
    __New(native := unset) {
        this.native := IsSet(native) ? native : WinCredentialNative()
    }

    Read(targetName, consumer) {
        targetName := this.ValidateTargetName(targetName)
        if !IsObject(consumer) || !HasMethod(consumer, "Call", 1)
            throw TypeError("Credential consumer must be callable")

        credential := this.native.ReadGeneric(targetName)
        try {
            blobSize := this.native.GetBlobSize(credential)
            this.ValidateBlobSize(blobSize)
            ownedCopy := this.native.CopyBlob(this.native.GetBlobPointer(credential), blobSize)
            try {
                ; AutoHotkey creates a temporary String here. Its zeroization cannot be guaranteed.
                ; The String is exposed only for this synchronous callback and is never returned.
                consumer.Call(StrGet(ownedCopy.Ptr, blobSize // 2, "UTF-16"))
            } finally {
                this.native.WipeBlob(ownedCopy)
            }
        } finally {
            this.native.FreeCredential(credential)
        }
    }

    ValidateTargetName(targetName) {
        targetName := Trim(String(targetName))
        if (targetName = "") || (StrLen(targetName) > 32767) || RegExMatch(targetName, "[\r\n]")
            throw ValueError("Credential target name is invalid")
        return targetName
    }

    ValidateBlobSize(blobSize) {
        if (blobSize < 0) || Mod(blobSize, 2) != 0 || (blobSize > 2560)
            throw Error("Credential blob size is invalid")
    }
}

class WinCredentialNative {
    ReadGeneric(targetName) {
        credential := 0
        if !DllCall("Advapi32.dll\CredReadW", "Str", targetName, "UInt", 1, "UInt", 0, "PtrP", &credential, "Int")
            throw Error("Credential is unavailable. Register the requested target before using this command.")
        return credential
    }

    GetBlobSize(credential) {
        return NumGet(credential, 16 + (2 * A_PtrSize), "UInt")
    }

    GetBlobPointer(credential) {
        blobPointerOffset := this.AlignToPointer(20 + (2 * A_PtrSize))
        return NumGet(credential, blobPointerOffset, "Ptr")
    }

    CopyBlob(blobPointer, byteCount) {
        if (byteCount > 0) && !blobPointer
            throw Error("Credential blob pointer is invalid")
        ownedCopy := Buffer(byteCount, 0)
        if (byteCount > 0)
            DllCall("Kernel32.dll\RtlMoveMemory", "Ptr", ownedCopy.Ptr, "Ptr", blobPointer, "UPtr", byteCount)
        return ownedCopy
    }

    WipeBlob(ownedCopy) {
        if (ownedCopy.Size > 0)
            DllCall("Kernel32.dll\RtlSecureZeroMemory", "Ptr", ownedCopy.Ptr, "UPtr", ownedCopy.Size, "Ptr")
    }

    FreeCredential(credential) {
        if credential
            DllCall("Advapi32.dll\CredFree", "Ptr", credential)
    }

    AlignToPointer(offset) {
        return (offset + A_PtrSize - 1) & ~(A_PtrSize - 1)
    }
}
