#Requires AutoHotkey v2.0

class SafeLogger {
    __New(rootDir := A_ScriptDir) {
        rootDir := String(rootDir)
        this.logDir := rootDir "\var\logs"
        try DirCreate(this.logDir)
    }

    static Redact(value) {
        value := String(value)
        ; Keep the field name and remove only the value. The boundary prevents
        ; a following field from being swallowed when logs are space-delimited.
        value := RegExReplace(value, "i)(password|secret|clipboard)\s*=\s*([^\s;,&#]+)", "$1=[REDACTED]")
        value := RegExReplace(value, "i)(credentialblob)\s*=\s*([^\s;,&#]+)", "$1=[REDACTED]")
        value := RegExReplace(value, "i)(password|secret|clipboard)\s*:\s*([^\s;,&#]+)", "$1:[REDACTED]")
        value := RegExReplace(value, "i)(credentialblob)\s*:\s*([^\s;,&#]+)", "$1:[REDACTED]")
        return value
    }

    Log(level, message) {
        level := StrLower(Trim(String(level)))
        if (level = "")
            level := "info"
        line := FormatTime(, "yyyy-MM-dd HH:mm:ss") " [" level "] " SafeLogger.Redact(message) "`n"
        try {
            DirCreate(this.logDir)
            FileAppend(line, this.logDir "\hub.log", "UTF-8")
            return true
        } catch {
            return false
        }
    }

    Write(level, message) {
        return this.Log(level, message)
    }
}
