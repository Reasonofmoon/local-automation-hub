[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot '..\scripts\Open-OrcaAiWorkspace.ps1'

function ConvertTo-TestArgument {
    param([Parameter(Mandatory)][string]$Value)

    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $backslashes++
            continue
        }
        if ($character -eq '"') {
            [void]$builder.Append('\', ($backslashes * 2) + 1)
            [void]$builder.Append('"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) {
            [void]$builder.Append('\', $backslashes)
            $backslashes = 0
        }
        [void]$builder.Append($character)
    }
    if ($backslashes -gt 0) {
        [void]$builder.Append('\', $backslashes * 2)
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Invoke-TestProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [int]$TimeoutMs = 15000
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.Arguments = [string]::Join(' ', ($Arguments | ForEach-Object {
        ConvertTo-TestArgument -Value ([string]$_)
    }))

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            return [pscustomobject]@{ Output = ''; Error = 'process did not start'; ExitCode = -1; TimedOut = $false }
        }
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($TimeoutMs)
        if ($timedOut) {
            $process.Kill()
            $process.WaitForExit()
        }
        [System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($outputTask, $errorTask))
        return [pscustomobject]@{
            Output = $outputTask.Result
            Error = $errorTask.Result
            ExitCode = if ($timedOut) { -1 } else { $process.ExitCode }
            TimedOut = $timedOut
        }
    } finally {
        $process.Dispose()
    }
}

function Assert-Condition {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $Condition) {
        throw "FAIL: $Message"
    }
}

function Assert-Equal {
    param(
        [Parameter(Mandatory)]$Expected,
        [Parameter(Mandatory)]$Actual,
        [Parameter(Mandatory)][string]$Message
    )
    if ($Expected -ne $Actual) {
        throw "FAIL: $Message (expected '$Expected', actual '$Actual')"
    }
}

function New-FakeOrcaFixture {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ScenarioName
    )

    $fakeRoot = Join-Path $Root 'fake-orca'
    New-Item -ItemType Directory -Path $fakeRoot -Force | Out-Null
    $script = Join-Path $fakeRoot 'fake-orca.ps1'
    $launcher = Join-Path $fakeRoot 'orca.cmd'
    $scriptText = @'
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CliArguments
)

$scenario = Get-Content -LiteralPath $env:FAKE_ORCA_SCENARIO -Raw | ConvertFrom-Json
$call = [ordered]@{
    command = if ($CliArguments.Count -gt 0) { $CliArguments[0] } else { '' }
    arguments = @($CliArguments)
}
Add-Content -LiteralPath $env:FAKE_ORCA_CALL_LOG -Value ($call | ConvertTo-Json -Compress -Depth 8)

function Get-ArgumentValue {
    param([string]$Name)
    $index = [Array]::IndexOf($CliArguments, $Name)
    if ($index -ge 0 -and $index + 1 -lt $CliArguments.Count) {
        return $CliArguments[$index + 1]
    }
    return ''
}

function Send-Envelope {
    param($Result)
    $envelope = [ordered]@{
        ok = if ([bool]$scenario.stringOk) { 'true' } else { $true }
        result = $Result
    }
    [Console]::Error.WriteLine(('FAKE_ENVELOPE=' + ($envelope | ConvertTo-Json -Compress -Depth 12)))
    $envelope | ConvertTo-Json -Compress -Depth 12
}

$operation = if ($CliArguments.Count -gt 1 -and @('repo', 'terminal') -contains $CliArguments[0]) {
    "$($CliArguments[0]) $($CliArguments[1])"
} elseif ($CliArguments.Count -gt 0) {
    $CliArguments[0]
} else {
    ''
}
switch ($operation) {
    'status' {
        $runtime = [ordered]@{ state = [string]$scenario.runtimeState; reachable = [bool]$scenario.runtimeReachable }
        Send-Envelope ([ordered]@{ runtime = $runtime })
    }
    'repo list' {
        $repositories = @()
        if ([bool]$scenario.repositoryRegistered) {
            $repositories = @([ordered]@{ id = 'repo-1'; path = [string]$scenario.repositoryRoot })
        }
        Send-Envelope ([ordered]@{ repositories = $repositories })
    }
    'repo add' {
        Send-Envelope ([ordered]@{ id = 'repo-1'; path = (Get-ArgumentValue -Name '--path') })
    }
    'terminal list' {
        $terminals = @()
        if ([bool]$scenario.existingTerminal) {
            $terminals = @([ordered]@{
                handle = 'terminal-existing-codex'
                title = '  Codex  '
                command = 'codex'
                worktree = "path:$([string]$scenario.repositoryRoot)"
                state = 'live'
            })
        }
        if ([bool]$scenario.listCreatedTerminals) {
            $createdCalls = @(Get-Content -LiteralPath $env:FAKE_ORCA_CALL_LOG | ForEach-Object {
                $_ | ConvertFrom-Json
            } | Where-Object {
                $_.command -eq 'terminal' -and $_.arguments -contains 'create'
            })
            foreach ($createdCall in $createdCalls) {
                $titleIndex = [Array]::IndexOf([object[]]$createdCall.arguments, '--title')
                $commandIndex = [Array]::IndexOf([object[]]$createdCall.arguments, '--command')
                $worktreeIndex = [Array]::IndexOf([object[]]$createdCall.arguments, '--worktree')
                $title = [string]$createdCall.arguments[$titleIndex + 1]
                $command = [string]$createdCall.arguments[$commandIndex + 1]
                $worktree = [string]$createdCall.arguments[$worktreeIndex + 1]
                $terminals += [ordered]@{
                    handle = "terminal-$($title.ToLowerInvariant())"
                    title = $title
                    command = $command
                    worktree = $worktree
                    state = 'live'
                }
            }
        }
        Send-Envelope ([ordered]@{ terminals = $terminals })
    }
    'terminal create' {
        $title = Get-ArgumentValue -Name '--title'
        if ([string]$scenario.createFailureAgent -eq $title) {
            [ordered]@{ ok = $false; error = 'fake create failure' } | ConvertTo-Json -Compress
        } else {
            $handle = "terminal-$($title.ToLowerInvariant())"
            switch ([string]$scenario.createResponseShape) {
                'terminal' { Send-Envelope ([ordered]@{ terminal = [ordered]@{ handle = $handle } }) }
                'startupTerminal' { Send-Envelope ([ordered]@{ startupTerminal = [ordered]@{ handle = $handle } }) }
                'none' { Send-Envelope ([ordered]@{ created = $true; workspace = [ordered]@{ id = 'worktree-sensitive-value' } }) }
                'unrelatedIds' { Send-Envelope ([ordered]@{ id = 'repo-sensitive-value'; result = [ordered]@{ id = 'result-sensitive-value' }; worktree = [ordered]@{ id = 'worktree-sensitive-value' } }) }
                default { Send-Envelope ([ordered]@{ handle = $handle }) }
            }
        }
    }
    'terminal wait' {
        $terminalHandle = Get-ArgumentValue -Name '--terminal'
        $waitFailureHandle = if ([string]::IsNullOrWhiteSpace([string]$scenario.waitFailureAgent)) {
            ''
        } else {
            $waitFailureName = ([string]$scenario.waitFailureAgent).ToLowerInvariant()
            "terminal-$waitFailureName"
        }
        if ([bool]$scenario.waitFailure -and ([string]::IsNullOrWhiteSpace($waitFailureHandle) -or $terminalHandle -eq $waitFailureHandle)) {
            [ordered]@{ ok = $false; error = 'fake wait failure' } | ConvertTo-Json -Compress
        } else {
            Send-Envelope ([ordered]@{ state = 'tui-idle' })
        }
    }
    default {
        [ordered]@{ ok = $false; error = "unexpected operation $operation" } | ConvertTo-Json -Compress
    }
}
'@
    Set-Content -LiteralPath $script -Value $scriptText -Encoding UTF8
    Set-Content -LiteralPath $launcher -Value "@powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"%~dp0fake-orca.ps1`" %*" -Encoding ASCII

    return [pscustomobject]@{ Command = $launcher; Root = $fakeRoot }
}

function New-FakeAgent {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Name
    )
    $path = Join-Path $Root "$Name.cmd"
    Set-Content -LiteralPath $path -Value "@echo fake-$Name" -Encoding ASCII
    return $path
}

function Invoke-Adapter {
    param(
        [Parameter(Mandatory)][string]$SelectedPath,
        [Parameter(Mandatory)][string]$OrcaCommand,
        [Parameter(Mandatory)][hashtable]$AgentCommandPaths,
        [int]$ReadyTimeoutMs = 1000
    )

    $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
    $arguments = @(
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy', 'Bypass',
        '-File', $scriptPath,
        '-SelectedPath', $SelectedPath,
        '-OrcaCommand', $OrcaCommand,
        '-GitCommand', 'git',
        '-ReadyTimeoutMs', [string]$ReadyTimeoutMs,
        '-AgentCommandPathsJson', ($AgentCommandPaths | ConvertTo-Json -Compress)
    )
    $process = Invoke-TestProcess -FilePath $powershell -Arguments $arguments -TimeoutMs 30000
    $parsed = $null
    if (-not [string]::IsNullOrWhiteSpace($process.Output)) {
        $parsed = $process.Output.Trim() | ConvertFrom-Json
    }
    return [pscustomobject]@{ Process = $process; Result = $parsed }
}

if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    $missing = Invoke-TestProcess -FilePath (Get-Command powershell.exe).Source -Arguments @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath,
        '-SelectedPath', (Get-Location).Path
    )
    Assert-Condition ($missing.ExitCode -ne 0) 'missing adapter script produces the expected RED failure'
    Write-Error 'RED: scripts/Open-OrcaAiWorkspace.ps1 is missing'
    exit 1
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('orca-ai-workspace-test-' + [guid]::NewGuid().ToString('N'))
$repositoryRoot = Join-Path $tempRoot 'repo'
$nestedPath = Join-Path $repositoryRoot 'src\nested'
$nonGitPath = Join-Path $tempRoot 'not-a-repo'
$fakeAgentRoot = Join-Path $tempRoot 'fake-agents'
$callLog = Join-Path $tempRoot 'orca-calls.jsonl'
$scenarioPath = Join-Path $tempRoot 'scenario.json'
$oldScenario = $env:FAKE_ORCA_SCENARIO
$oldCallLog = $env:FAKE_ORCA_CALL_LOG
$gitCommand = (Get-Command git -ErrorAction Stop).Source

try {
    New-Item -ItemType Directory -Path $repositoryRoot, $nestedPath, $nonGitPath, $fakeAgentRoot -Force | Out-Null
    & $gitCommand -C $repositoryRoot init --quiet | Out-Null
    $agentPaths = @{}
    foreach ($agentName in @('codex', 'claude', 'grok', 'gemini')) {
        $agentPaths[$agentName] = New-FakeAgent -Root $fakeAgentRoot -Name $agentName
    }
    $fake = New-FakeOrcaFixture -Root $tempRoot -ScenarioName 'default'
    $env:FAKE_ORCA_CALL_LOG = $callLog
    $env:FAKE_ORCA_SCENARIO = $scenarioPath

    $scenario = [ordered]@{
        runtimeState = 'ready'
        runtimeReachable = $true
        repositoryRoot = $repositoryRoot
        repositoryRegistered = $false
        existingTerminal = $false
        createFailureAgent = ''
        waitFailure = $false
        waitFailureAgent = ''
        stringOk = $false
        createResponseShape = 'flat'
        listCreatedTerminals = $false
    }
    $scenario | ConvertTo-Json -Compress | Set-Content -LiteralPath $scenarioPath -Encoding UTF8
    $basic = Invoke-Adapter -SelectedPath $nestedPath -OrcaCommand $fake.Command -AgentCommandPaths $agentPaths
    Assert-Equal 0 $basic.Process.ExitCode 'basic adapter invocation exits successfully'
    Assert-Condition $basic.Result.success "basic result succeeds (exit=$($basic.Process.ExitCode); stderr=$($basic.Process.Error); output=$($basic.Process.Output); resultError=$($basic.Result.error))"
    Assert-Equal $repositoryRoot ([IO.Path]::GetFullPath($basic.Result.repositoryRoot)) 'nested selection resolves to Git root'
    Assert-Equal 4 @($basic.Result.created).Count 'creates four missing terminals'
    Assert-Equal 0 @($basic.Result.reused).Count 'does not report missing terminals as reused'
    $calls = @(Get-Content -LiteralPath $callLog | ForEach-Object { $_ | ConvertFrom-Json })
    Assert-Condition (-not ($calls.command -contains 'worktree')) 'never requests a worktree operation'
    Assert-Condition (-not ($calls.command -contains 'send')) 'never sends a terminal message'
    $createCalls = @($calls | Where-Object { $_.command -eq 'terminal' -and $_.arguments -contains 'create' })
    Assert-Equal 4 $createCalls.Count 'creates exactly four Orca terminals'
    foreach ($call in $createCalls) {
        Assert-Condition ($call.arguments -contains "path:$repositoryRoot") 'terminal operation uses the exact path selector'
    }

    foreach ($nestedShape in @('terminal', 'startupTerminal')) {
        $scenario.createResponseShape = $nestedShape
        $scenario | ConvertTo-Json -Compress | Set-Content -LiteralPath $scenarioPath -Encoding UTF8
        Remove-Item -LiteralPath $callLog -Force -ErrorAction SilentlyContinue
        $nested = Invoke-Adapter -SelectedPath $nestedPath -OrcaCommand $fake.Command -AgentCommandPaths $agentPaths
        Assert-Condition $nested.Result.success "$nestedShape create response succeeds"
        Assert-Equal 4 @($nested.Result.created).Count "$nestedShape create response supplies all handles"
        Assert-Equal 0 @($nested.Result.failed).Count "$nestedShape create response has no failures"
    }

    $scenario.createResponseShape = 'none'
    $scenario.listCreatedTerminals = $true
    $scenario | ConvertTo-Json -Compress | Set-Content -LiteralPath $scenarioPath -Encoding UTF8
    Remove-Item -LiteralPath $callLog -Force -ErrorAction SilentlyContinue
    $reconciled = Invoke-Adapter -SelectedPath $nestedPath -OrcaCommand $fake.Command -AgentCommandPaths $agentPaths
    Assert-Condition $reconciled.Result.success 'handle-less create responses reconcile through terminal list'
    Assert-Equal 4 @($reconciled.Result.created).Count 'reconciled terminals remain classified as created'
    Assert-Equal 0 @($reconciled.Result.reused).Count 'reconciled terminals are not misclassified as reused'
    Assert-Equal 0 @($reconciled.Result.failed).Count 'reconciled terminals have no failures'
    $reconcileCalls = @(Get-Content -LiteralPath $callLog | ForEach-Object { $_ | ConvertFrom-Json })
    Assert-Equal 4 @($reconcileCalls | Where-Object { $_.command -eq 'terminal' -and $_.arguments -contains 'create' }).Count 'each agent is created only once during reconciliation'
    Assert-Equal 5 @($reconcileCalls | Where-Object { $_.command -eq 'terminal' -and $_.arguments -contains 'list' }).Count 'each handle-less create performs one bounded reconciliation list'

    $scenario.createResponseShape = 'unrelatedIds'
    $scenario.listCreatedTerminals = $false
    $scenario | ConvertTo-Json -Compress | Set-Content -LiteralPath $scenarioPath -Encoding UTF8
    Remove-Item -LiteralPath $callLog -Force -ErrorAction SilentlyContinue
    $unrelatedIds = Invoke-Adapter -SelectedPath $nestedPath -OrcaCommand $fake.Command -AgentCommandPaths $agentPaths
    Assert-Equal 4 @($unrelatedIds.Result.failed).Count 'unrelated repository and worktree IDs are not terminal handles'
    Assert-Condition ($unrelatedIds.Result.failed[0].reason -like '*response keys: id, result, worktree*') 'missing handle failure reports response shape keys'
    Assert-Condition ($unrelatedIds.Result.failed[0].reason -notlike '*sensitive-value*') 'missing handle failure does not expose response values'
    $unrelatedCalls = @(Get-Content -LiteralPath $callLog | ForEach-Object { $_ | ConvertFrom-Json })
    Assert-Equal 0 @($unrelatedCalls | Where-Object { $_.command -eq 'terminal' -and $_.arguments -contains 'wait' }).Count 'unrelated IDs are never passed to terminal wait'

    $scenario.createResponseShape = 'flat'

    Remove-Item -LiteralPath $callLog -Force
    $nonGitResult = Invoke-Adapter -SelectedPath $nonGitPath -OrcaCommand $fake.Command -AgentCommandPaths $agentPaths
    Assert-Condition (-not $nonGitResult.Result.success) 'non-Git folder is rejected'
    Assert-Equal 0 @(Get-Content -LiteralPath $callLog -ErrorAction SilentlyContinue).Count 'non-Git rejection performs no Orca call'

    $scenario.runtimeState = 'starting'
    $scenario | ConvertTo-Json -Compress | Set-Content -LiteralPath $scenarioPath -Encoding UTF8
    Remove-Item -LiteralPath $callLog -Force -ErrorAction SilentlyContinue
    $starting = Invoke-Adapter -SelectedPath $nestedPath -OrcaCommand $fake.Command -AgentCommandPaths $agentPaths
    Assert-Condition (-not $starting.Result.success) 'starting runtime is rejected'
    $startingCalls = @(Get-Content -LiteralPath $callLog | ForEach-Object { $_ | ConvertFrom-Json })
    Assert-Equal 1 $startingCalls.Count 'runtime rejection stops before repository mutation'
    Assert-Equal 'status' $startingCalls[0].command 'runtime validation is the first Orca call'
    Assert-Condition ($starting.Result.error -like 'Orca runtime is starting*') 'runtime rejection explains the observed state and recovery action'

    $scenario.runtimeState = 'ready'
    $scenario.existingTerminal = $true
    $scenario.repositoryRegistered = $true
    $scenario | ConvertTo-Json -Compress | Set-Content -LiteralPath $scenarioPath -Encoding UTF8
    Remove-Item -LiteralPath $callLog -Force -ErrorAction SilentlyContinue
    $emptyInjectedPaths = Invoke-Adapter -SelectedPath $nestedPath -OrcaCommand $fake.Command -AgentCommandPaths @{}
    Assert-Condition $emptyInjectedPaths.Result.success 'empty injected paths do not trigger a StrictMode property error'

    Remove-Item -LiteralPath $callLog -Force -ErrorAction SilentlyContinue
    $reused = Invoke-Adapter -SelectedPath $nestedPath -OrcaCommand $fake.Command -AgentCommandPaths $agentPaths
    Assert-Condition $reused.Result.success 'existing terminal scenario succeeds'
    Assert-Equal 1 @($reused.Result.reused).Count 'live matching terminal is reused'
    Assert-Equal 3 @($reused.Result.created).Count 'remaining agents are created'
    $reusedCalls = @(Get-Content -LiteralPath $callLog | ForEach-Object { $_ | ConvertFrom-Json })
    Assert-Equal 3 @($reusedCalls | Where-Object { $_.command -eq 'terminal' -and $_.arguments -contains 'create' }).Count 'reused terminal is not recreated'

    $missingAgentPaths = @{
        codex = $agentPaths.codex
        claude = $agentPaths.claude
        grok = $agentPaths.grok
        gemini = (Join-Path $fakeAgentRoot 'missing-gemini.cmd')
    }
    $scenario.existingTerminal = $false
    $scenario.repositoryRegistered = $false
    $scenario | ConvertTo-Json -Compress | Set-Content -LiteralPath $scenarioPath -Encoding UTF8
    Remove-Item -LiteralPath $callLog -Force -ErrorAction SilentlyContinue
    $missing = Invoke-Adapter -SelectedPath $nestedPath -OrcaCommand $fake.Command -AgentCommandPaths $missingAgentPaths
    Assert-Equal 1 @($missing.Result.skipped).Count 'missing CLI is skipped'
    Assert-Equal 'Gemini' $missing.Result.skipped[0].agent 'missing CLI identifies Gemini'
    Assert-Equal 3 @($missing.Result.created).Count 'available CLIs continue after a missing CLI'

    $scenario.createFailureAgent = 'Claude'
    $scenario | ConvertTo-Json -Compress | Set-Content -LiteralPath $scenarioPath -Encoding UTF8
    Remove-Item -LiteralPath $callLog -Force -ErrorAction SilentlyContinue
    $partial = Invoke-Adapter -SelectedPath $nestedPath -OrcaCommand $fake.Command -AgentCommandPaths $agentPaths
    Assert-Condition $partial.Result.success "partial agent failure keeps the workspace result usable (exit=$($partial.Process.ExitCode); stderr=$($partial.Process.Error); output=$($partial.Process.Output))"
    Assert-Equal 1 @($partial.Result.failed).Count 'one agent create failure is isolated'
    Assert-Equal 'Claude' $partial.Result.failed[0].agent 'failure identifies the affected agent'
    Assert-Equal 3 @($partial.Result.created).Count 'later agents continue after one create failure'

    $scenario.createFailureAgent = ''
    $scenario.waitFailure = $true
    $scenario.waitFailureAgent = 'Codex'
    $scenario | ConvertTo-Json -Compress | Set-Content -LiteralPath $scenarioPath -Encoding UTF8
    Remove-Item -LiteralPath $callLog -Force -ErrorAction SilentlyContinue
    $waitPartial = Invoke-Adapter -SelectedPath $nestedPath -OrcaCommand $fake.Command -AgentCommandPaths $agentPaths
    Assert-Condition $waitPartial.Result.success 'wait failure keeps the workspace result usable'
    Assert-Equal 1 @($waitPartial.Result.failed).Count 'one wait failure is isolated'
    Assert-Equal 'Codex' $waitPartial.Result.failed[0].agent 'wait failure identifies the affected agent'
    Assert-Equal 3 @($waitPartial.Result.created).Count 'later agents are created after a wait failure'
    $waitCalls = @(Get-Content -LiteralPath $callLog | ForEach-Object { $_ | ConvertFrom-Json })
    Assert-Equal 4 @($waitCalls | Where-Object { $_.command -eq 'terminal' -and $_.arguments -contains 'create' }).Count 'wait failure does not stop later terminal creation'

    $scenario.waitFailure = $false
    $scenario.waitFailureAgent = ''
    $scenario.stringOk = $true
    $scenario | ConvertTo-Json -Compress | Set-Content -LiteralPath $scenarioPath -Encoding UTF8
    Remove-Item -LiteralPath $callLog -Force -ErrorAction SilentlyContinue
    $stringEnvelope = Invoke-Adapter -SelectedPath $nestedPath -OrcaCommand $fake.Command -AgentCommandPaths $agentPaths
    Assert-Condition (-not $stringEnvelope.Result.success) 'string true envelope is rejected'
    Assert-Equal 1 @(Get-Content -LiteralPath $callLog | ForEach-Object { $_ | ConvertFrom-Json }).Count 'string envelope rejection stops after status'

    $lookupFailurePaths = @{
        codex = (Join-Path $fakeAgentRoot 'missing-codex.cmd')
        claude = (Join-Path $fakeAgentRoot 'missing-claude.cmd')
        grok = (Join-Path $fakeAgentRoot 'missing-grok.cmd')
        gemini = (Join-Path $fakeAgentRoot 'missing-gemini.cmd')
    }
    $scenario.stringOk = $false
    $scenario | ConvertTo-Json -Compress | Set-Content -LiteralPath $scenarioPath -Encoding UTF8
    Remove-Item -LiteralPath $callLog -Force -ErrorAction SilentlyContinue
    $lookupFailure = Invoke-Adapter -SelectedPath $nestedPath -OrcaCommand $fake.Command -AgentCommandPaths $lookupFailurePaths
    Assert-Condition $lookupFailure.Result.success 'command lookup failure keeps workspace result usable'
    Assert-Equal 4 @($lookupFailure.Result.skipped).Count 'lookup failures map every agent to skipped'
    Assert-Equal 0 @(Get-Content -LiteralPath $callLog | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.command -eq 'terminal' -and $_.arguments -contains 'create' }).Count 'lookup failures do not launch agent terminals'

    Write-Host 'PASS: Orca AI workspace adapter'
} finally {
    if ($null -eq $oldScenario) { Remove-Item Env:FAKE_ORCA_SCENARIO -ErrorAction SilentlyContinue } else { $env:FAKE_ORCA_SCENARIO = $oldScenario }
    if ($null -eq $oldCallLog) { Remove-Item Env:FAKE_ORCA_CALL_LOG -ErrorAction SilentlyContinue } else { $env:FAKE_ORCA_CALL_LOG = $oldCallLog }
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
