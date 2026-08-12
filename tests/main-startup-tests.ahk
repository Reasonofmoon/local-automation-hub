#Requires AutoHotkey v2.0
#Include TestSupport.ahk

global MAIN_STARTUP_HEADLESS := true
#Include ..\main.ahk

startupError := ""
try {
    repositoryRoot := RegExReplace(A_ScriptDir, "\\tests$", "")
    startupHub := InitializeHub(repositoryRoot, false)
} catch as caughtError {
    startupError := caughtError.Message
}

AssertEqual("", startupError, "headless startup composition registers built-in commands")
if (startupError = "") {
    startupRegistry := startupHub["registry"]
    AssertTrue(startupRegistry.Search("workspace").Length > 0, "startup registers workspace commands")
    AssertTrue(startupRegistry.Search("window").Length > 0, "startup registers window commands")
    AssertTrue(startupRegistry.Search("organize").Length > 0, "startup registers file commands")
}

ExitWithTestResult()
