#Requires AutoHotkey v2.0
#Include TestSupport.ahk
#Include ..\src\modules\CredentialStore.ahk

nativeWipe := WinCredentialNative()
ownedBuffer := Buffer(8, 0)
loop ownedBuffer.Size {
    NumPut("UChar", A_Index, ownedBuffer, A_Index - 1)
}
try {
    nativeWipe.WipeBlob(ownedBuffer)
} catch as caught {
    FileAppend("FAIL: native credential buffer wipe call (" caught.Message ")`n", "*")
    ExitApp(1)
}
loop ownedBuffer.Size {
    AssertTrue(NumGet(ownedBuffer, A_Index - 1, "UChar") = 0, "native credential buffer byte is wiped")
}

missingStore := CredentialStore()
AssertThrows(() => missingStore.Read("LocalAutomationHub/Test/DefinitelyMissing", (*) => 0), "missing generic credential is actionable")
AssertThrows(() => missingStore.Read("", (*) => 0), "empty target is rejected")
AssertThrows(() => missingStore.Read("LocalAutomationHub/Test/Valid", "not callable"), "consumer must be callable")

native := FakeCredentialNative("scope-value")
store := CredentialStore(native)
global ScopedValueSeen := false
store.Read("LocalAutomationHub/Test/Scoped", ScopedCredentialConsumer)
AssertTrue(ScopedValueSeen, "secret text is available only in consumer callback")
AssertTrue(native.WasWiped(), "owned native copy is wiped after consumer returns")
AssertTrue(native.WasFreed(), "original credential is freed after consumer returns")

throwingNative := FakeCredentialNative("throwing-value")
throwingStore := CredentialStore(throwingNative)
AssertThrows(() => throwingStore.Read("LocalAutomationHub/Test/Throwing", ThrowingCredentialConsumer), "consumer errors propagate")
AssertTrue(throwingNative.WasWiped(), "owned native copy is wiped when consumer throws")
AssertTrue(throwingNative.WasFreed(), "original credential is freed when consumer throws")

invalidBlobNative := FakeCredentialNative("bad")
invalidBlobNative.blobSize := 3
invalidBlobStore := CredentialStore(invalidBlobNative)
AssertThrows(() => invalidBlobStore.Read("LocalAutomationHub/Test/BadBlob", (*) => 0), "odd UTF-16 blob size is rejected")
AssertTrue(invalidBlobNative.WasFreed(), "original credential is freed after invalid blob")

ExitWithTestResult()

ThrowingCredentialConsumer(*) {
    throw Error("consumer failure")
}

ScopedCredentialConsumer(value) {
    global ScopedValueSeen
    ScopedValueSeen := value = "scope-value"
}

class FakeCredentialNative {
    __New(value) {
        this.source := Buffer((StrLen(value) + 1) * 2, 0)
        StrPut(value, this.source, "UTF-16")
        this.blobSize := StrLen(value) * 2
        this.wiped := false
        this.freed := false
    }

    ReadGeneric(targetName) {
        return this.source
    }

    GetBlobSize(credential) {
        return this.blobSize
    }

    GetBlobPointer(credential) {
        return credential.Ptr
    }

    CopyBlob(blobPointer, byteCount) {
        copy := Buffer(byteCount, 0)
        loop byteCount
            NumPut("UChar", NumGet(blobPointer + A_Index - 1, "UChar"), copy, A_Index - 1)
        return copy
    }

    WipeBlob(copy) {
        loop copy.Size {
            NumPut("UChar", 0, copy, A_Index - 1)
        }
        loop copy.Size {
            if NumGet(copy, A_Index - 1, "UChar") != 0
                throw Error("Fake credential buffer wipe failed")
        }
        this.wiped := true
    }

    FreeCredential(credential) {
        this.freed := true
    }

    WasWiped() {
        return this.wiped
    }

    WasFreed() {
        return this.freed
    }
}
