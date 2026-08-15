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
    AssertTrue(startupHub.Has("inputAdapter"), "headless composition exposes the shared input adapter")
    AssertTrue(startupHub.Has("inputAdapter") && startupHub["palette"].targetHandoff = startupHub["inputAdapter"], "palette shares the snippet input adapter")
    AssertTrue(startupHub.Has("snippets") && startupHub["snippets"].inputAdapter = startupHub["inputAdapter"], "snippet service shares the shared input adapter")
    startupRegistry := startupHub["registry"]
    startupSnippetService := startupHub["snippets"]
    for snippetId, _ in startupSnippetService.snippets
        AssertEqual(1, CountStartupCommandId(startupRegistry, "snippet." snippetId), "registers configured snippet command: " snippetId)
    AssertTrue(startupRegistry.Search("workspace").Length > 0, "startup registers workspace commands")
    startupHasOrcaCommand := false
    for _, startupCommand in startupRegistry.All() {
        if (startupCommand["id"] = "workspace.ai-development") {
            startupHasOrcaCommand := true
            break
        }
    }
    AssertTrue(startupHasOrcaCommand, "headless startup registers workspace.ai-development")
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

CountStartupCommandId(registry, expectedId) {
    count := 0
    for _, command in registry.All() {
        if (command["id"] = expectedId)
            count += 1
    }
    return count
}
