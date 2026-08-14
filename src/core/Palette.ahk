#Requires AutoHotkey v2.0

class CommandPalette {
    __New(registry, context, targetHandoff := unset) {
        this.registry := registry
        this.context := context
        this.targetHandoff := IsSet(targetHandoff) ? targetHandoff : ""
        if IsObject(this.targetHandoff) && !HasMethod(this.targetHandoff, "CaptureBeforePalette")
            throw TypeError("Palette target handoff must provide CaptureBeforePalette")
        this.query := ""
        this.results := []
        this.selectedIndex := 0
        this.isVisible := false
        this.gui := false
        this.editControl := false
        this.listView := false
        this.keyHandler := ObjBindMethod(this, "HandleKeyDown")
        this.SetQuery("")
    }

    SetQuery(query) {
        this.query := String(query)
        this.results := this.registry.Search(this.query)
        this.selectedIndex := this.results.Length > 0 ? 1 : 0
        return this.results
    }

    VisibleCommandIds() {
        ids := []
        for command in this.results
            ids.Push(command["id"])
        return ids
    }

    SelectIndex(index) {
        index := Integer(index)
        if (index < 1 || index > this.results.Length)
            throw ValueError("Palette selection is out of range")
        this.selectedIndex := index
        if IsObject(this.listView)
            this.listView.Modify(index, "Select Focus Vis")
        return index
    }

    ExecuteSelection() {
        if (this.selectedIndex < 1 || this.selectedIndex > this.results.Length) {
            this.context.Notify("No command is selected", "warn")
            return Map("success", false, "error", "No command selected")
        }

        command := this.results[this.selectedIndex]
        this.Hide()
        try result := this.registry.Invoke(command["id"], this.context)
        catch error {
            this.context.Notify(SafeErrorMessage(error), "error")
            return Map("success", false, "error", SafeErrorMessage(error))
        }

        if IsObject(result) && result is Map && result.Has("success") && !result["success"]
            this.context.Notify(result.Has("error") ? result["error"] : "Command failed", "error")
        return result
    }

    Show() {
        this.CaptureTargetBeforeShow()
        this.ShowGui()
        this.isVisible := true
        return true
    }

    ShowGui() {
        this.EnsureGui()
        this.SetQuery("")
        this.editControl.Value := ""
        this.RenderResults()
        this.gui.Show()
        this.editControl.Focus()
    }

    CaptureTargetBeforeShow() {
        if IsObject(this.targetHandoff) {
            try return this.targetHandoff.CaptureBeforePalette()
            catch as caughtError {
                this.context.Notify(SafeErrorMessage(caughtError), "warn")
            }
        }
        return ""
    }

    Hide(*) {
        if IsObject(this.gui)
            this.gui.Hide()
        this.isVisible := false
        return true
    }

    IsOpen() {
        return this.isVisible
    }

    EnsureGui() {
        if IsObject(this.gui)
            return

        this.gui := Gui("+AlwaysOnTop -MinimizeBox", "Local Automation Hub")
        this.gui.MarginX := 12
        this.gui.MarginY := 12
        this.editControl := this.gui.AddEdit("w520", "")
        this.listView := this.gui.AddListView("w520 r9 -Multi -Hdr", ["Command", "Id"])
        this.listView.ModifyCol(1, 350)
        this.listView.ModifyCol(2, 160)
        this.editControl.OnEvent("Change", ObjBindMethod(this, "OnQueryChange"))
        this.listView.OnEvent("ItemSelect", ObjBindMethod(this, "OnListSelection"))
        this.listView.OnEvent("DoubleClick", ObjBindMethod(this, "OnListDoubleClick"))
        this.gui.OnEvent("Escape", ObjBindMethod(this, "Hide"))
        this.gui.OnEvent("Close", ObjBindMethod(this, "Hide"))
        OnMessage(0x100, this.keyHandler)
    }

    OnQueryChange(editControl, *) {
        this.SetQuery(editControl.Value)
        this.RenderResults()
    }

    OnListSelection(_, row, selected) {
        if selected && row >= 1 && row <= this.results.Length
            this.selectedIndex := row
    }

    OnListDoubleClick(_, row) {
        if row >= 1 && row <= this.results.Length {
            this.selectedIndex := row
            this.ExecuteSelection()
        }
    }

    HandleKeyDown(wParam, lParam, msg, hwnd) {
        if !this.isVisible || !IsObject(this.gui)
            return
        rootHwnd := DllCall("GetAncestor", "ptr", hwnd, "uint", 2, "ptr")
        if (rootHwnd != this.gui.Hwnd)
            return

        return this.RouteKeyDown(wParam, lParam, msg, true)
    }

    RouteKeyDown(wParam, lParam, msg, isPaletteWindow) {
        if !this.isVisible || !isPaletteWindow || (msg != 0x100)
            return

        if (wParam = 0x0D) {
            this.ExecuteSelection()
            return 0
        }
        if (wParam = 0x1B) {
            this.Hide()
            return 0
        }
        if (wParam >= 0x31 && wParam <= 0x39) {
            index := wParam - 0x30
            if (index <= this.results.Length) {
                this.SelectIndex(index)
                this.ExecuteSelection()
            }
            return 0
        }
    }

    RenderResults() {
        if !IsObject(this.listView)
            return
        this.listView.Delete()
        for command in this.results
            this.listView.Add("", command["label"], command["id"])
        if (this.selectedIndex > 0)
            this.listView.Modify(this.selectedIndex, "Select Focus Vis")
    }
}
