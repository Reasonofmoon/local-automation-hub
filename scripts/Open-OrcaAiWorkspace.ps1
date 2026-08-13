[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SelectedPath,

    [string]$OrcaCommand = 'orca',

    [string]$GitCommand = 'git',

    [int]$ReadyTimeoutMs = 60000,

    # Tests may inject executable paths without depending on the user's PATH.
    [string]$AgentCommandPathsJson = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$agentDefinitions = @(
    [pscustomobject]@{ Title = 'Codex'; Command = 'codex' }
    [pscustomobject]@{ Title = 'Claude'; Command = 'claude' }
    [pscustomobject]@{ Title = 'Grok'; Command = 'grok' }
    [pscustomobject]@{ Title = 'Gemini'; Command = 'gemini' }
)

function ConvertTo-ProcessArgument {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value
    )

    # ProcessStartInfo on Windows PowerShell 5.1 exposes one command-line
    # string, so quote each array element using the Windows argv rules.
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

function Invoke-BoundedProcess {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [Parameter(Mandatory)]
        [int]$TimeoutMs
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.Arguments = [string]::Join(' ', ($Arguments | ForEach-Object {
        ConvertTo-ProcessArgument -Value ([string]$_)
    }))

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $timedOut = $false
    try {
        try {
            if (-not $process.Start()) {
                return [pscustomobject]@{
                    Started  = $false
                    ExitCode = -1
                    TimedOut = $false
                    Output   = ''
                    Error    = ''
                }
            }
        } catch {
            return [pscustomobject]@{
                Started  = $false
                ExitCode = -1
                TimedOut = $false
                Output   = ''
                Error    = $_.Exception.Message
            }
        }

        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        $waitMs = [Math]::Max(1, $TimeoutMs)
        $timedOut = -not $process.WaitForExit($waitMs)
        if ($timedOut) {
            try {
                if (-not $process.HasExited) {
                    $process.Kill()
                }
            } catch {
                # The owned process may have exited between the checks.
            }
            $process.WaitForExit()
        }
        [System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($outputTask, $errorTask))
        return [pscustomobject]@{
            Started  = $true
            ExitCode = if ($timedOut) { -1 } else { $process.ExitCode }
            TimedOut = $timedOut
            Output   = $outputTask.Result
            Error    = $errorTask.Result
        }
    } finally {
        $process.Dispose()
    }
}

function Get-ObjectProperty {
    param(
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory)]
        [string[]]$Names
    )

    if ($null -eq $Object) {
        return $null
    }
    foreach ($name in $Names) {
        foreach ($property in $Object.PSObject.Properties) {
            if ($property.Name -eq $name) {
                return $property.Value
            }
        }
    }
    return $null
}

function Test-ObjectProperty {
    param(
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $Object) {
        return $false
    }
    foreach ($property in $Object.PSObject.Properties) {
        if ($property.Name -eq $Name) {
            return $true
        }
    }
    return $false
}

function Test-OrcaEnvelope {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType] -or $Value -is [array]) {
        return $false
    }
    $id = Get-ObjectProperty -Object $Value -Names @('id')
    $ok = Get-ObjectProperty -Object $Value -Names @('ok')
    if ([string]::IsNullOrWhiteSpace([string]$id) -or $ok -isnot [bool]) {
        return $false
    }
    if ($ok) {
        return Test-ObjectProperty -Object $Value -Name 'result'
    }
    return Test-ObjectProperty -Object $Value -Name 'error'
}

function ConvertTo-SafeOrcaErrorText {
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$Operation,

        [int]$ExitCode = 0
    )

    $code = ''
    $message = ''
    if ($null -ne $Value -and $Value -isnot [string] -and $Value -isnot [ValueType]) {
        $codeValue = Get-ObjectProperty -Object $Value -Names @('code', 'errorCode')
        $messageValue = Get-ObjectProperty -Object $Value -Names @('message', 'detail', 'reason')
        if ($null -ne $codeValue -and ($codeValue -is [string] -or $codeValue -is [ValueType])) {
            $code = [string]$codeValue
        }
        if ($null -ne $messageValue -and ($messageValue -is [string] -or $messageValue -is [ValueType])) {
            $message = [string]$messageValue
        }
    } elseif ($null -ne $Value -and ($Value -is [string] -or $Value -is [ValueType])) {
        $message = [string]$Value
    }

    # Keep only bounded, printable code/message fields; never serialize raw
    # Orca error objects because they may carry terminal or credential data.
    $code = [regex]::Replace($code, '[^\x20-\x7E]', '').Trim()
    $message = [regex]::Replace($message, '[^\x20-\x7E]', ' ').Trim()
    if ($code.Length -gt 120) {
        $code = $code.Substring(0, 120)
    }
    if ($message.Length -gt 500) {
        $message = $message.Substring(0, 500)
    }

    $parts = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($code)) {
        $parts.Add("code=$code")
    }
    if (-not [string]::IsNullOrWhiteSpace($message)) {
        $parts.Add("message=$message")
    }
    if ($parts.Count -eq 0) {
        if ($ExitCode -ne 0) {
            return "Orca $Operation failed (exit code $ExitCode)."
        }
        return "Orca $Operation rejected the request."
    }
    return "Orca $Operation rejected the request: $($parts -join '; ')."
}

function ConvertFrom-OrcaFramedJson {
    param(
        [Parameter(Mandatory)][string]$Output,
        [Parameter(Mandatory)][string]$Operation
    )

    $maxCharacters = 1048576
    $allLines = @($Output -split "`r?`n")
    $nonEmptyLines = @($allLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($Output.Length -gt $maxCharacters) {
        throw "Orca $Operation returned unusable JSON framing (lines=$($nonEmptyLines.Count); candidates=0; shape=over-limit)."
    }

    $candidateTexts = [System.Collections.Generic.List[string]]::new()
    $objectStart = -1
    $depth = 0
    $inString = $false
    $escaped = $false
    for ($index = 0; $index -lt $Output.Length; $index++) {
        $character = $Output[$index]
        if ($depth -eq 0) {
            if ($character -eq '{') {
                $objectStart = $index
                $depth = 1
                $inString = $false
                $escaped = $false
            }
            continue
        }
        if ($inString) {
            if ($escaped) {
                $escaped = $false
            } elseif ($character -eq '\') {
                $escaped = $true
            } elseif ($character -eq '"') {
                $inString = $false
            }
            continue
        }
        if ($character -eq '"') {
            $inString = $true
        } elseif ($character -eq '{') {
            $depth++
        } elseif ($character -eq '}') {
            $depth--
            if ($depth -eq 0) {
                $candidateTexts.Add($Output.Substring($objectStart, $index - $objectStart + 1))
                $objectStart = -1
            }
        }
    }

    $envelopes = [System.Collections.Generic.List[object]]::new()
    foreach ($candidateText in $candidateTexts) {
        try {
            $candidate = $candidateText | ConvertFrom-Json
        } catch {
            continue
        }
        if (Test-OrcaEnvelope -Value $candidate) {
            $envelopes.Add($candidate)
        }
    }
    if ($envelopes.Count -ne 1) {
        $shape = if ($nonEmptyLines.Count -eq 1) { 'single-line' } else { 'multi-line' }
        throw "Orca $Operation returned unusable JSON framing (lines=$($nonEmptyLines.Count); candidates=$($envelopes.Count); shape=$shape)."
    }
    return $envelopes[0]
}

function Invoke-OrcaJson {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [Parameter(Mandatory)]
        [string]$Operation
    )

    $process = Invoke-BoundedProcess -FilePath $OrcaCommand -Arguments $Arguments -TimeoutMs $ReadyTimeoutMs
    if (-not $process.Started) {
        throw "Orca command unavailable while running $Operation."
    }
    if ($process.TimedOut) {
        throw "Orca $Operation timed out."
    }
    if ([string]::IsNullOrWhiteSpace($process.Output)) {
        if ($process.ExitCode -ne 0) {
            throw (ConvertTo-SafeOrcaErrorText -Value $null -Operation $Operation -ExitCode $process.ExitCode)
        }
        throw "Orca $Operation returned no JSON."
    }

    try {
        $envelope = ConvertFrom-OrcaFramedJson -Output $process.Output -Operation $Operation
    } catch {
        if ($process.ExitCode -ne 0) {
            throw (ConvertTo-SafeOrcaErrorText -Value $null -Operation $Operation -ExitCode $process.ExitCode)
        }
        throw
    }
    $ok = Get-ObjectProperty -Object $envelope -Names @('ok')
    if ($ok -isnot [bool]) {
        throw "Orca $Operation returned an invalid ok flag."
    }
    if (-not $ok) {
        $errorValue = Get-ObjectProperty -Object $envelope -Names @('error')
        throw (ConvertTo-SafeOrcaErrorText -Value $errorValue -Operation $Operation -ExitCode $process.ExitCode)
    }
    $result = Get-ObjectProperty -Object $envelope -Names @('result')
    if ($null -eq $result) {
        throw "Orca $Operation returned no result."
    }
    return $result
}

function Resolve-GitRoot {
    $process = Invoke-BoundedProcess -FilePath $GitCommand -Arguments @(
        '-C', $SelectedPath, 'rev-parse', '--show-toplevel'
    ) -TimeoutMs $ReadyTimeoutMs
    if (-not $process.Started -or $process.TimedOut -or $process.ExitCode -ne 0) {
        throw 'Selected path is not a Git checkout.'
    }
    $gitRoot = $process.Output.Trim()
    if ([string]::IsNullOrWhiteSpace($gitRoot)) {
        throw 'Selected path is not a Git checkout.'
    }
    try {
        return [IO.Path]::GetFullPath($gitRoot)
    } catch {
        throw 'Git returned an invalid repository root.'
    }
}

function Normalize-PathValue {
    param([Parameter(Mandatory)][string]$Path)
    try {
        return ([IO.Path]::GetFullPath($Path)).TrimEnd('\')
    } catch {
        return $Path.Trim().TrimEnd('\')
    }
}

function Test-SamePath {
    param(
        [AllowEmptyString()][string]$Left,
        [AllowEmptyString()][string]$Right
    )
    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) {
        return $false
    }
    return [StringComparer]::OrdinalIgnoreCase.Equals(
        (Normalize-PathValue -Path $Left),
        (Normalize-PathValue -Path $Right)
    )
}

function Get-AgentCommandPaths {
    if ([string]::IsNullOrWhiteSpace($AgentCommandPathsJson)) {
        return [pscustomobject]@{}
    }
    try {
        $value = $AgentCommandPathsJson | ConvertFrom-Json
    } catch {
        throw 'Injected agent command paths are invalid JSON.'
    }
    if ($null -eq $value) {
        return [pscustomobject]@{}
    }
    return $value
}

function Resolve-AgentExecutable {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][object]$InjectedPaths
    )

    $injected = Get-ObjectProperty -Object $InjectedPaths -Names @($Command)
    if ($null -ne $injected -and -not [string]::IsNullOrWhiteSpace([string]$injected)) {
        $candidate = [string]$injected
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
        return $null
    }

    $whereCommand = Join-Path ([Environment]::GetFolderPath('System')) 'where.exe'
    if (-not (Test-Path -LiteralPath $whereCommand -PathType Leaf)) {
        $whereCommand = 'where.exe'
    }
    $lookup = Invoke-BoundedProcess -FilePath $whereCommand -Arguments @($Command) -TimeoutMs $ReadyTimeoutMs
    if (-not $lookup.Started -or $lookup.TimedOut -or $lookup.ExitCode -ne 0) {
        return $null
    }
    foreach ($line in ([string]$lookup.Output -split "`r?`n")) {
        $candidate = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }
    return $null
}

function Test-LiveTerminal {
    param([Parameter(Mandatory)][object]$Terminal)
    $state = [string](Get-ObjectProperty -Object $Terminal -Names @('state', 'status', 'lifecycle'))
    if ([string]::IsNullOrWhiteSpace($state)) {
        return $false
    }
    return @('live', 'running', 'ready', 'tui-idle', 'active') -contains $state.Trim().ToLowerInvariant()
}

function Test-TerminalWorkspace {
    param(
        [Parameter(Mandatory)][object]$Terminal,
        [Parameter(Mandatory)][string]$Selector,
        [Parameter(Mandatory)][string]$RepositoryRoot
    )
    $workspace = Get-ObjectProperty -Object $Terminal -Names @(
        'worktree', 'workspace', 'workspacePath', 'worktreePath', 'selector'
    )
    if ($null -eq $workspace) {
        return $false
    }
    $workspaceText = ([string]$workspace).Trim()
    if ([StringComparer]::OrdinalIgnoreCase.Equals($workspaceText, $Selector)) {
        return $true
    }
    return Test-SamePath -Left $workspaceText -Right $RepositoryRoot
}

function Find-MatchingTerminal {
    param(
        [object[]]$Terminals = @(),
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string]$Selector,
        [Parameter(Mandatory)][string]$RepositoryRoot
    )
    foreach ($terminal in $Terminals) {
        if ($null -eq $terminal) {
            continue
        }
        if (-not (Test-LiveTerminal -Terminal $terminal)) {
            continue
        }
        $terminalTitle = ([string](Get-ObjectProperty -Object $terminal -Names @('title', 'name'))).Trim()
        $terminalCommand = [string](Get-ObjectProperty -Object $terminal -Names @(
            'command', 'commandName', 'executable', 'commandIdentity'
        ))
        if (-not [StringComparer]::OrdinalIgnoreCase.Equals($terminalTitle, $Title)) {
            continue
        }
        if (-not [StringComparer]::OrdinalIgnoreCase.Equals($terminalCommand.Trim(), $Command)) {
            continue
        }
        if (Test-TerminalWorkspace -Terminal $terminal -Selector $Selector -RepositoryRoot $RepositoryRoot) {
            return $terminal
        }
    }
    return $null
}

function Get-TerminalHandle {
    param([Parameter(Mandatory)][object]$Terminal)

    $handle = Get-ObjectProperty -Object $Terminal -Names @('handle', 'terminalId')
    if ($null -ne $handle -and -not [string]::IsNullOrWhiteSpace([string]$handle)) {
        return [string]$handle
    }

    foreach ($containerName in @('terminal', 'startupTerminal', 'session', 'result')) {
        $container = Get-ObjectProperty -Object $Terminal -Names @($containerName)
        if ($null -eq $container -or $container -is [string] -or $container -is [ValueType]) {
            continue
        }
        $nestedHandleNames = if ($containerName -eq 'result') {
            @('handle', 'terminalId')
        } else {
            @('handle', 'terminalId', 'id')
        }
        $nestedHandle = Get-ObjectProperty -Object $container -Names $nestedHandleNames
        if ($null -ne $nestedHandle -and -not [string]::IsNullOrWhiteSpace([string]$nestedHandle)) {
            return [string]$nestedHandle
        }
        $recursiveHandle = Get-TerminalHandle -Terminal $container
        if ($null -ne $recursiveHandle) {
            return $recursiveHandle
        }
    }
    return $null
}

function Get-ResponseShapeKeys {
    param([Parameter(Mandatory)][object]$Response)

    $keys = @($Response.PSObject.Properties | ForEach-Object { $_.Name })
    if ($keys.Count -eq 0) {
        return '<none>'
    }
    return ($keys -join ', ')
}

$summary = [ordered]@{
    success        = $false
    repositoryRoot = ''
    created        = @()
    reused         = @()
    skipped        = @()
    failed         = @()
    error          = ''
}

try {
    $repositoryRoot = Resolve-GitRoot
    $summary.repositoryRoot = $repositoryRoot
    $selector = "path:$repositoryRoot"

    $status = Invoke-OrcaJson -Arguments @('status', '--json') -Operation 'status'
    $runtime = Get-ObjectProperty -Object $status -Names @('runtime')
    $runtimeState = ([string](Get-ObjectProperty -Object $runtime -Names @('state'))).Trim().ToLowerInvariant()
    $runtimeReachableValue = Get-ObjectProperty -Object $runtime -Names @('reachable')
    $runtimeReachable = if ($runtimeReachableValue -is [bool]) {
        $runtimeReachableValue
    } else {
        ([string]$runtimeReachableValue).Trim().ToLowerInvariant() -eq 'true'
    }
    if ($runtimeState -ne 'ready' -or -not $runtimeReachable) {
        throw "Orca runtime is $runtimeState (reachable=$runtimeReachable). Wait until Orca is ready, then try again."
    }

    $repositoryList = Invoke-OrcaJson -Arguments @('repo', 'list', '--json') -Operation 'repository list'
    $repositories = @(Get-ObjectProperty -Object $repositoryList -Names @('repositories', 'repos'))
    $registered = $false
    foreach ($repository in $repositories) {
        $registeredPath = Get-ObjectProperty -Object $repository -Names @(
            'path', 'root', 'repositoryRoot', 'worktreePath'
        )
        if (Test-SamePath -Left ([string]$registeredPath) -Right $repositoryRoot) {
            $registered = $true
            break
        }
    }
    if (-not $registered) {
        [void](Invoke-OrcaJson -Arguments @('repo', 'add', '--path', $repositoryRoot, '--json') -Operation 'repository add')
    }

    $terminalList = Invoke-OrcaJson -Arguments @(
        'terminal', 'list', '--worktree', $selector, '--json'
    ) -Operation 'terminal list'
    $terminals = @(Get-ObjectProperty -Object $terminalList -Names @('terminals'))
    $injectedPaths = Get-AgentCommandPaths
    $created = [System.Collections.Generic.List[string]]::new()
    $reused = [System.Collections.Generic.List[string]]::new()
    $skipped = [System.Collections.Generic.List[object]]::new()
    $failed = [System.Collections.Generic.List[object]]::new()

    foreach ($agent in $agentDefinitions) {
        $executable = Resolve-AgentExecutable -Command $agent.Command -InjectedPaths $injectedPaths
        if ($null -eq $executable) {
            $skipped.Add([pscustomobject]@{ agent = $agent.Title; reason = 'command not found' })
            continue
        }

        $existing = Find-MatchingTerminal -Terminals $terminals -Title $agent.Title `
            -Command $agent.Command -Selector $selector -RepositoryRoot $repositoryRoot
        if ($null -ne $existing) {
            $reused.Add($agent.Title)
            continue
        }

        try {
            $createdResult = Invoke-OrcaJson -Arguments @(
                'terminal', 'create', '--worktree', $selector,
                '--title', $agent.Title, '--command', $agent.Command, '--json'
            ) -Operation "terminal create $($agent.Title)"
            $handle = Get-TerminalHandle -Terminal $createdResult
            if ($null -eq $handle) {
                $reconciledList = Invoke-OrcaJson -Arguments @(
                    'terminal', 'list', '--worktree', $selector, '--json'
                ) -Operation "terminal list after create $($agent.Title)"
                $reconciledTerminals = @(Get-ObjectProperty -Object $reconciledList -Names @('terminals'))
                $reconciled = Find-MatchingTerminal -Terminals $reconciledTerminals -Title $agent.Title `
                    -Command $agent.Command -Selector $selector -RepositoryRoot $repositoryRoot
                if ($null -ne $reconciled) {
                    $handle = Get-TerminalHandle -Terminal $reconciled
                }
            }
            if ($null -eq $handle) {
                $shapeKeys = Get-ResponseShapeKeys -Response $createdResult
                throw "Orca created the terminal but no terminal handle could be reconciled (response keys: $shapeKeys)."
            }
            $waitResult = Invoke-OrcaJson -Arguments @(
                'terminal', 'wait', '--terminal', $handle,
                '--for', 'tui-idle', '--timeout-ms', [string]$ReadyTimeoutMs, '--json'
            ) -Operation "terminal wait $($agent.Title)"
            $wait = Get-ObjectProperty -Object $waitResult -Names @('wait')
            if ($null -eq $wait -or $wait -is [string] -or $wait -is [ValueType]) {
                throw 'Orca terminal wait returned no wait result.'
            }
            $satisfied = Get-ObjectProperty -Object $wait -Names @('satisfied')
            if ($satisfied -isnot [bool]) {
                throw 'Orca terminal wait returned an invalid satisfied flag.'
            }
            # A valid wait envelope with satisfied=false means the newly
            # created CLI is alive but waiting for the user (for example,
            # permissions, trust, or auth selection). It remains created;
            # only create/transport errors belong in failed.
            $created.Add($agent.Title)
        } catch {
            $failed.Add([pscustomobject]@{ agent = $agent.Title; reason = $_.Exception.Message })
        }
    }

    $summary.created = @($created)
    $summary.reused = @($reused)
    $summary.skipped = @($skipped)
    $summary.failed = @($failed)
    $summary.success = $true
} catch {
    $summary.error = "$($_.Exception.Message) [line $($_.InvocationInfo.ScriptLineNumber)]"
    [Console]::Error.WriteLine("Orca AI workspace adapter: $($summary.error)")
}

$summary | ConvertTo-Json -Compress -Depth 12
