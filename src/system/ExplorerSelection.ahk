#Requires AutoHotkey v2.0

class ExplorerSelection {
    __New(adapter := unset) {
        this.adapter := IsSet(adapter) ? adapter : ComExplorerSelectionAdapter()
        if !IsObject(this.adapter) || !HasMethod(this.adapter, "GetActiveSelectedItems") || !HasMethod(this.adapter, "GetItemPath") || !HasMethod(this.adapter, "GetAttributes")
            throw TypeError("Explorer selection adapter must provide selected items, paths, and attributes")
    }

    GetRegularFiles() {
        selectedItems := this.adapter.GetActiveSelectedItems()
        if !IsObject(selectedItems)
            throw Error("No items are selected in the active Explorer window")

        paths := []
        seenPaths := Map()
        for _, item in selectedItems {
            path := NormalizeExplorerPath(this.adapter.GetItemPath(item))
            attributes := this.adapter.GetAttributes(path)
            if (attributes = "") || InStr(attributes, "D") || InStr(attributes, "H") || InStr(attributes, "S")
                continue
            key := StrLower(path)
            if seenPaths.Has(key)
                continue
            seenPaths[key] := true
            paths.Push(path)
        }
        if (paths.Length = 0)
            throw Error("Select at least one regular, visible file in Explorer")
        return paths
    }
}

class ComExplorerSelectionAdapter {
    GetActiveSelectedItems() {
        shell := ComObject("Shell.Application")
        activeHandle := WinExist("A")
        for _, window in shell.Windows {
            try {
                if (window.HWND = activeHandle)
                    return window.Document.SelectedItems
            }
        }
        throw Error("The active window is not an Explorer window")
    }

    GetItemPath(item) {
        return item.Path
    }

    GetAttributes(path) {
        return FileGetAttrib(path)
    }
}

NormalizeExplorerPath(path) {
    path := Trim(String(path))
    if (path = "")
        throw ValueError("Explorer selection contains an empty path")

    requiredLength := DllCall("Kernel32.dll\GetFullPathNameW", "Str", path, "UInt", 0, "Ptr", 0, "Ptr", 0, "UInt")
    if (requiredLength = 0)
        throw OSError(A_LastError, "GetFullPathNameW", path)
    pathBuffer := Buffer((requiredLength + 1) * 2, 0)
    resolvedLength := DllCall("Kernel32.dll\GetFullPathNameW", "Str", path, "UInt", requiredLength + 1, "Ptr", pathBuffer.Ptr, "Ptr", 0, "UInt")
    if (resolvedLength = 0 || resolvedLength > requiredLength)
        throw OSError(A_LastError, "GetFullPathNameW", path)
    return StrGet(pathBuffer, resolvedLength)
}
