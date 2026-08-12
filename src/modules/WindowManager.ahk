#Requires AutoHotkey v2.0

class WindowManager {
    __New(adapter) {
        if !IsObject(adapter)
            throw TypeError("Window adapter must be an object")
        this.adapter := adapter
    }

    MoveActive(position) {
        windowHandle := this.adapter.GetActiveWindow()
        if !windowHandle
            throw Error("No active window")
        monitorIndex := this.adapter.GetMonitorForWindow(windowHandle)
        workArea := this.adapter.GetMonitorWorkArea(monitorIndex)
        rect := WindowManager.CalculateRect(workArea, position)
        return this.adapter.MoveWindow(windowHandle, rect["left"], rect["top"], rect["width"], rect["height"])
    }

    MoveToMonitor(direction) {
        windowHandle := this.adapter.GetActiveWindow()
        if !windowHandle
            throw Error("No active window")
        monitorCount := this.adapter.GetMonitorCount()
        if (monitorCount < 2)
            return false
        currentMonitor := this.adapter.GetMonitorForWindow(windowHandle)
        destination := WindowManager.GetDestinationMonitor(currentMonitor, monitorCount, direction)
        rect := this.adapter.GetWindowRect(windowHandle)
        targetRect := WindowManager.ClampRect(rect, this.adapter.GetMonitorWorkArea(destination))
        return this.adapter.MoveWindow(windowHandle, targetRect["left"], targetRect["top"], targetRect["width"], targetRect["height"])
    }

    static CalculateRect(workArea, position) {
        WindowManager.ValidateWorkArea(workArea)
        position := StrLower(Trim(String(position)))
        left := Integer(workArea["left"])
        top := Integer(workArea["top"])
        width := Integer(workArea["right"]) - left
        height := Integer(workArea["bottom"]) - top
        if (position = "full")
            return Map("left", left, "top", top, "width", width, "height", height)
        if !(position = "left" || position = "right")
            throw ValueError("Window position must be left, right, or full")
        halfWidth := Floor(width / 2)
        return Map(
            "left", position = "left" ? left : left + halfWidth,
            "top", top,
            "width", position = "left" ? halfWidth : width - halfWidth,
            "height", height
        )
    }

    static ClampRect(rect, workArea) {
        WindowManager.ValidateRectangle(rect)
        WindowManager.ValidateWorkArea(workArea)
        width := Min(Integer(rect["right"]) - Integer(rect["left"]), Integer(workArea["right"]) - Integer(workArea["left"]))
        height := Min(Integer(rect["bottom"]) - Integer(rect["top"]), Integer(workArea["bottom"]) - Integer(workArea["top"]))
        left := Max(Integer(workArea["left"]), Min(Integer(rect["left"]), Integer(workArea["right"]) - width))
        top := Max(Integer(workArea["top"]), Min(Integer(rect["top"]), Integer(workArea["bottom"]) - height))
        return Map("left", left, "top", top, "width", width, "height", height)
    }

    static GetDestinationMonitor(currentMonitor, monitorCount, direction) {
        direction := StrLower(Trim(String(direction)))
        if !(direction = "left" || direction = "right")
            throw ValueError("Monitor direction must be left or right")
        destination := currentMonitor + (direction = "left" ? -1 : 1)
        if (destination < 1)
            return monitorCount
        if (destination > monitorCount)
            return 1
        return destination
    }

    static ValidateWorkArea(area) {
        WindowManager.ValidateRectangle(area)
    }

    static ValidateRectangle(area) {
        if !IsObject(area) || !area.Has("left") || !area.Has("top") || !area.Has("right") || !area.Has("bottom")
            throw ValueError("Rectangle requires left, top, right, and bottom")
        if (Integer(area["right"]) <= Integer(area["left"]) || Integer(area["bottom"]) <= Integer(area["top"]))
            throw ValueError("Rectangle must have positive size")
    }
}

class Win32WindowAdapter {
    GetActiveWindow() {
        return WinExist("A")
    }

    GetWindowRect(windowHandle) {
        WinGetPos(&left, &top, &width, &height, "ahk_id " windowHandle)
        return Map("left", left, "top", top, "right", left + width, "bottom", top + height)
    }

    GetMonitorForWindow(windowHandle) {
        rect := this.GetWindowRect(windowHandle)
        centerX := rect["left"] + Floor((rect["right"] - rect["left"]) / 2)
        centerY := rect["top"] + Floor((rect["bottom"] - rect["top"]) / 2)
        loop MonitorGetCount() {
            MonitorGet(A_Index, &left, &top, &right, &bottom)
            if (centerX >= left && centerX < right && centerY >= top && centerY < bottom)
                return A_Index
        }
        return MonitorGetPrimary()
    }

    GetMonitorWorkArea(monitorIndex) {
        MonitorGetWorkArea(monitorIndex, &left, &top, &right, &bottom)
        return Map("left", left, "top", top, "right", right, "bottom", bottom)
    }

    GetMonitorCount() {
        return MonitorGetCount()
    }

    MoveWindow(windowHandle, left, top, width, height) {
        WinMove(left, top, width, height, "ahk_id " windowHandle)
        return true
    }
}

RegisterWindowCommands(registry, service) {
    for _, position in ["left", "right", "full"] {
        registry.Register(
            "window." position,
            "Window: " position,
            ["window", "layout"],
            "low",
            MoveActiveWindow.Bind(service, position)
        )
    }
    for _, direction in ["left", "right"] {
        registry.Register(
            "window.monitor-" direction,
            "Window monitor: " direction,
            ["window", "monitor"],
            "low",
            MoveWindowToMonitor.Bind(service, direction)
        )
    }
}

MoveActiveWindow(service, position, *) {
    return service.MoveActive(position)
}

MoveWindowToMonitor(service, direction, *) {
    return service.MoveToMonitor(direction)
}
