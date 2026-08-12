#Requires AutoHotkey v2.0

class SafeLogger {
    __New(rootDir := A_ScriptDir) {
        rootDir := String(rootDir)
        this.logDir := rootDir "\var\logs"
        try DirCreate(this.logDir)
    }

    static Redact(value) {
        value := String(value)
        ; A following key/value field, delimiter, or end-of-line terminates the
        ; secret so whitespace inside an unquoted value cannot leak.
        value := RegExReplace(value, "i)(password|secret|clipboard|credential_?blob)\s*([=:])\s*.*?(?=\s+[A-Za-z][A-Za-z0-9_.-]*\s*[=:]|[;,&#\r\n]|$)", "$1$2[REDACTED]")
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
