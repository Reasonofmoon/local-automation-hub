#Requires AutoHotkey v2.0
#Include TestSupport.ahk
#Include ..\src\modules\Workspaces.ahk

class FakeWorkspaceRunner {
    __New(runOutcomes := Map()) {
        this.runOutcomes := runOutcomes
        this.activatedApps := []
        this.ranValues := []
    }

    ActivateApp(path) {
        if (path = "already-open.exe") {
            this.activatedApps.Push(path)
            return true
        }
        return false
    }

    Run(value) {
        this.ranValues.Push(value)
        if this.runOutcomes.Has(value) && !this.runOutcomes[value]
            throw Error("Launch failed: " value)
        return true
    }
}

runner := FakeWorkspaceRunner(Map("bad.exe", false))
service := WorkspaceService(runner)
result := service.RunItems(["app|notepad.exe", "app|bad.exe", "url|https://localhost/"])
AssertEqual(2, result["succeeded"].Length, "continues after a failed item")
AssertEqual(1, result["failed"].Length, "reports failed item")
AssertEqual("bad.exe", result["failed"][1]["value"], "records failed item value")

activeResult := service.RunItems(["app|already-open.exe"])
AssertEqual(1, activeResult["skipped"].Length, "marks an already-open app as skipped")
AssertEqual("already-open.exe", runner.activatedApps[1], "activates an existing app")
AssertEqual(3, runner.ranValues.Length, "does not run an existing app again")

invalidResult := service.RunItems(["app|", "unknown|item", "url|https://valid.example|extra"])
AssertEqual(3, invalidResult["failed"].Length, "rejects malformed workspace items")

modes := Map("development", Map("Items", ["folder|C:\Projects"]))
modeRunner := FakeWorkspaceRunner()
modeService := WorkspaceService(modeRunner, modes)
modeResult := modeService.RunMode("development")
AssertEqual(1, modeResult["succeeded"].Length, "runs configured workspace modes")
missingModeResult := modeService.RunMode("missing")
AssertEqual(1, missingModeResult["failed"].Length, "reports an unknown workspace mode")

ExitWithTestResult()
