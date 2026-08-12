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

    diagnosticPresenterCalls := []
    diagnosticPresentedReport := []
    diagnosticRegistry := CommandRegistry()
    RegisterSystemDiagnostics(diagnosticRegistry, startupHub["context"], CaptureDiagnosticsReport.Bind(diagnosticPresenterCalls, diagnosticPresentedReport))
    diagnosticResult := diagnosticRegistry.Invoke("system.diagnostics", startupHub["context"])
    AssertTrue(diagnosticResult["success"], "system diagnostics command succeeds")
    AssertEqual(1, diagnosticPresenterCalls.Length, "system diagnostics invokes its presenter once")
    AssertEqual(diagnosticResult["report"], diagnosticPresentedReport.Length > 0 ? diagnosticPresentedReport[1] : "", "system diagnostics presents the generated report")
    AssertTrue(InStr(diagnosticPresentedReport.Length > 0 ? diagnosticPresentedReport[1] : "", "Local Automation Hub diagnostics") > 0, "system diagnostics presenter receives readable report")
}

ExitWithTestResult()

CaptureDiagnosticsReport(calls, reports, presentedReport, *) {
    calls.Push(true)
    reports.Push(presentedReport)
    return true
}
