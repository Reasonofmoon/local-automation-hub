#Requires AutoHotkey v2.0

; Small assertion helpers shared by the AutoHotkey test scripts.
global TestFailures := 0

AssertTrue(condition, message := "assertion failed") {
    global TestFailures
    if !condition {
        TestFailures += 1
        OutputDebug("FAIL: " message)
        FileAppend("FAIL: " message "`n", "*")
    }
}

AssertFalse(condition, message := "expected false") {
    AssertTrue(!condition, message)
}

AssertEqual(expected, actual, message := "values differ") {
    global TestFailures
    if (expected != actual) {
        TestFailures += 1
        FileAppend("FAIL: " message " (expected=" FormatValue(expected) ", actual=" FormatValue(actual) ")`n", "*")
    }
}

AssertThrows(callback, message := "expected an exception") {
    global TestFailures
    threw := false
    try {
        callback()
    } catch {
        threw := true
    }
    if !threw {
        TestFailures += 1
        FileAppend("FAIL: " message "`n", "*")
    }
}

FormatValue(value) {
    if IsObject(value)
        return "[object]"
    return String(value)
}

ExitWithTestResult() {
    global TestFailures
    if (TestFailures = 0) {
        FileAppend("PASS`n", "*")
        ExitApp(0)
    }
    FileAppend("FAILURES=" TestFailures "`n", "*")
    ExitApp(1)
}
