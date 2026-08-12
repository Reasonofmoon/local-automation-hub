#Requires AutoHotkey v2.0
#Include TestSupport.ahk
#Include ..\src\modules\WindowManager.ahk

class FakeWindowAdapter {
    __New() {
        this.activeWindow := 100
        this.windowRect := Map("left", 100, "top", 100, "right", 900, "bottom", 700)
        this.monitorIndex := 1
        this.workAreas := Map(
            1, Map("left", 0, "top", 0, "right", 1920, "bottom", 1040),
            2, Map("left", 1920, "top", 0, "right", 3200, "bottom", 1000)
        )
        this.moves := []
    }

    GetActiveWindow() {
        return this.activeWindow
    }

    GetWindowRect(windowHandle) {
        return this.windowRect
    }

    GetMonitorForWindow(windowHandle) {
        return this.monitorIndex
    }

    GetMonitorWorkArea(monitorIndex) {
        return this.workAreas[monitorIndex]
    }

    GetMonitorCount() {
        return this.workAreas.Count
    }

    MoveWindow(windowHandle, left, top, width, height) {
        this.moves.Push(Map("left", left, "top", top, "width", width, "height", height))
        return true
    }
}

rect := WindowManager.CalculateRect(Map("left", 0, "top", 0, "right", 1920, "bottom", 1040), "left")
AssertEqual(960, rect["width"], "uses half work area")
AssertEqual(1040, rect["height"], "excludes taskbar")
rightRect := WindowManager.CalculateRect(Map("left", 0, "top", 0, "right", 1920, "bottom", 1040), "right")
AssertEqual(960, rightRect["left"], "aligns right position to the work area midpoint")
fullRect := WindowManager.CalculateRect(Map("left", 0, "top", 0, "right", 1920, "bottom", 1040), "full")
AssertEqual(1920, fullRect["width"], "fills the work area")

adapter := FakeWindowAdapter()
windowService := WindowManager(adapter)
AssertTrue(windowService.MoveActive("right"), "moves the active window using the current work area")
AssertEqual(960, adapter.moves[1]["left"], "moves active window to the right half")

adapter.windowRect := Map("left", 100, "top", 100, "right", 1100, "bottom", 900)
AssertTrue(windowService.MoveToMonitor("right"), "moves to the next monitor")
monitorMove := adapter.moves[2]
AssertEqual(1000, monitorMove["width"], "preserves width between monitors")
AssertEqual(800, monitorMove["height"], "preserves height between monitors")
AssertEqual(1920, monitorMove["left"], "clamps a moved window inside the destination work area")

oversized := WindowManager.ClampRect(Map("left", 0, "top", 0, "right", 2000, "bottom", 1200), Map("left", 1920, "top", 0, "right", 3200, "bottom", 1000))
AssertEqual(1280, oversized["width"], "shrinks an oversized window to destination width")
AssertEqual(1000, oversized["height"], "shrinks an oversized window to destination height")

ExitWithTestResult()
