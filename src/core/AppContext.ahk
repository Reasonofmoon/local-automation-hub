#Requires AutoHotkey v2.0

class AppContext {
    __New(rootDir, config, logger) {
        this.rootDir := String(rootDir)
        this.config := config
        this.logger := logger
        this.cancelled := false
        this.cancelReason := ""
        this.lastNotification := Map("message", "", "level", "info")
    }

    Cancel(reason := "Emergency stop") {
        this.cancelled := true
        this.cancelReason := String(reason)
        this.Notify(this.cancelReason, "warn")
        return true
    }

    ResetCancellation() {
        this.cancelled := false
        this.cancelReason := ""
        return true
    }

    IsCancelled() {
        return this.cancelled
    }

    Notify(message, level := "info") {
        this.lastNotification := Map("message", String(message), "level", String(level))
        try {
            if IsObject(this.logger)
                this.logger.Log(level, message)
        } catch {
            ; Diagnostics must never stop the caller's automation.
        }
        return this.lastNotification
    }
}
