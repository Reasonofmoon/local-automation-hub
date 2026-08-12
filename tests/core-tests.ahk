#Requires AutoHotkey v2.0
#Include TestSupport.ahk
#Include ..\src\core\AppContext.ahk
#Include ..\src\core\CommandRegistry.ahk
#Include ..\src\core\Config.ahk
#Include ..\src\core\Logger.ahk

testConfigPath := A_Temp "\local-automation-hub-core-test.ini"
try FileDelete(testConfigPath)
FileAppend("[General]`nKakaoPath=%TEMP%\\Kakao\\KakaoTalk.exe`nLogLevel=info`n`n[KakaoAccounts]`nwork=LocalAutomationHub/Kakao/work`n`n[Snippets]`nmultiline-prompt=First line\nSecond line`n`n[Workspace.development]`nItems=app|notepad.exe;folder|%USERPROFILE%\\Documents;url|https://localhost/`n", testConfigPath, "UTF-8")
config := HubConfig.Load(testConfigPath)
AssertTrue(config.Has("General"), "loads General section")
AssertTrue(InStr(config["General"]["KakaoPath"], EnvGet("TEMP")) = 1, "expands environment placeholders")
AssertEqual("First line`nSecond line", config["Snippets"]["multiline-prompt"], "decodes explicit newline")
AssertEqual("C:\Temp\Kakao\KakaoTalk.exe", DecodeConfigValue("C:\\Temp\\Kakao\\KakaoTalk.exe"), "decodes escaped backslashes")
AssertEqual(3, config["Workspace"]["development"]["Items"].Length, "parses workspace item list")
AssertEqual(0, HubConfig.Validate(config).Length, "accepts valid config")

logger := SafeLogger(A_Temp)
context := AppContext(A_ScriptDir, config, logger)
AssertFalse(context.IsCancelled(), "context starts active")
context.Cancel("test cancellation")
AssertTrue(context.IsCancelled(), "cancellation sets state")
context.ResetCancellation()
AssertFalse(context.IsCancelled(), "reset clears cancellation")

registry := CommandRegistry()
registry.Register("window.left", "Move left", ["window", "layout"], "low", (*) => "ok")
AssertEqual(1, registry.Search("layout").Length, "searches tags")
AssertThrows(() => registry.Register("window.left", "Duplicate", [], "low", (*) => 0), "rejects duplicate ids")
AssertEqual("ok", registry.Invoke("window.left", context), "invokes registered command")
registry.Register("window.bad", "Broken", [], "high", ThrowBoom)
invokeResult := registry.Invoke("window.bad", context)
AssertTrue(IsObject(invokeResult) && !invokeResult["success"], "isolates handler failure")

safe := SafeLogger.Redact("password=secret clipboard=private")
AssertFalse(InStr(safe, "secret"), "redacts password value")
AssertFalse(InStr(safe, "private"), "redacts clipboard value")
blobSafe := SafeLogger.Redact("CredentialBlob=example-secret CredentialBlobSize=12")
AssertFalse(InStr(blobSafe, "example-secret"), "redacts credential blob value")
AssertFalse(InStr(SafeLogger.Redact("password=secret;next=value"), "secret"), "redacts password before delimiter")
AssertTrue(InStr(SafeLogger.Redact("password=secret;next=value"), "next=value") > 0, "preserves following fields")
AssertFalse(InStr(SafeLogger.Redact("CredentialBlob: example-secret"), "example-secret"), "redacts credential blob with colon")
AssertThrows(() => registry.Register("bad.risk", "Bad risk", [], "critical", (*) => 0), "rejects unknown risk")
AssertThrows(() => registry.Register("", "Missing id", [], "low", (*) => 0), "rejects empty id")
AssertEqual("Command failed", SafeLogger.Redact("Command failed"), "redaction keeps ordinary errors")

invalidWorkspaceConfig := Map(
    "General", Map("KakaoPath", "C:\\KakaoTalk.exe"),
    "KakaoAccounts", Map(),
    "Snippets", Map(),
    "Workspace", Map("development", Map("Items", Map("one", "app|notepad.exe")))
)
AssertTrue(HubConfig.Validate(invalidWorkspaceConfig).Length > 0, "rejects non-array workspace items")
malformedConfig := Map(
    "General", "not-a-map",
    "KakaoAccounts", Map(),
    "Snippets", Map(),
    "Workspace", Map()
)
malformedErrors := "threw"
try malformedErrors := HubConfig.Validate(malformedConfig)
AssertTrue(IsObject(malformedErrors), "validates malformed config without throwing")
AssertTrue(malformedErrors.Length > 0, "reports malformed General section")
ExitWithTestResult()

ThrowBoom(*) {
    throw Error("boom")
}
