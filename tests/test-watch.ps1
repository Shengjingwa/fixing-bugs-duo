# Tests scripts/watch.ps1 against throwaway git worktrees.
# Without -Scenario it runs every scenario in its own process, so the ones that
# wait out the 1-minute thresholds overlap; it exits 1 if any check fails.
# Runs under Windows PowerShell 5.1 and PowerShell 7: watchers are started
# with the same executable as this script.
param([string]$Scenario = '', [string]$Root = '')

$ErrorActionPreference = 'Stop'
$watch = Join-Path $PSScriptRoot '..\skills\fixing-bugs-duo\scripts\watch.ps1'
$exe = (Get-Process -Id $PID).Path
$scenarios = @('not-git', 'events', 'stall', 'idle', 'running', 'edits', 'slow-repeat', 'slow-step', 'slow-turn')

function Quote([string]$s) { return '"' + $s + '"' }

if (-not $Scenario) {
    $Root = Join-Path ([IO.Path]::GetTempPath()) ('duo-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $Root | Out-Null
    Write-Output "PowerShell $($PSVersionTable.PSVersion) $exe"
    $runs = foreach ($s in $scenarios) {
        $log = Join-Path $Root "$s.log"
        $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Quote $PSCommandPath), '-Scenario', $s, '-Root', (Quote $Root))
        $p = Start-Process -FilePath $exe -ArgumentList $argv -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -PassThru
        [pscustomobject]@{ Name = $s; Log = $log; Proc = $p }
    }
    $failed = 0
    foreach ($run in $runs) {
        if (-not $run.Proc.WaitForExit(300000)) {
            Stop-Process -Id $run.Proc.Id -Force -ErrorAction SilentlyContinue
            Write-Output "FAIL $($run.Name) timed out"
            $failed++
        }
        $lines = @(Get-Content -LiteralPath $run.Log -ErrorAction SilentlyContinue)
        $lines | Write-Output
        $err = Get-Content -LiteralPath "$($run.Log).err" -Raw -ErrorAction SilentlyContinue
        if ($err) { Write-Output "stderr $($run.Name): $err" }
        $failed += @($lines | Where-Object { $_ -like 'FAIL *' }).Count
        if (-not ($lines -contains "DONE $($run.Name)")) {
            Write-Output "FAIL $($run.Name) did not finish"
            $failed++
        }
    }
    Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
    if ($failed) {
        Write-Output "$failed check(s) failed"
        exit 1
    }
    Write-Output 'all checks passed'
    exit 0
}

$script:watcher = $null
$script:watchOut = ''
$script:t0 = Get-Date

# Results bypass the pipeline so helpers that return values can still report.
function Say([string]$Text) { [Console]::Out.WriteLine($Text) }
function Pass([string]$Msg) { Say "PASS $Scenario $Msg" }
function Fail([string]$Msg) { Say "FAIL $Scenario $Msg" }
function Check([bool]$Ok, [string]$Msg) { if ($Ok) { Pass $Msg } else { Fail $Msg } }

function Invoke-Git {
    $ErrorActionPreference = 'Continue'
    $out = & git @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' '): $out" }
    return "$out".Trim()
}

function New-Worktree {
    $base = Join-Path $Root $Scenario
    $main = Join-Path $base 'main'
    $wt = Join-Path $base 'wt'
    New-Item -ItemType Directory -Path $main -Force | Out-Null
    Invoke-Git -C $main init -q | Out-Null
    Invoke-Git -C $main config user.name duo-test | Out-Null
    Invoke-Git -C $main config user.email duo-test@localhost | Out-Null
    Invoke-Git -C $main config commit.gpgsign false | Out-Null
    Invoke-Git -C $main config core.autocrlf false | Out-Null
    [IO.File]::WriteAllText((Join-Path $main 'a.txt'), "a`n")
    Invoke-Git -C $main add a.txt | Out-Null
    Invoke-Git -C $main commit -q -m init | Out-Null
    Invoke-Git -C $main worktree add -q -b fix/x $wt | Out-Null
    $gitDir = Invoke-Git -C $wt rev-parse --absolute-git-dir
    $duo = Join-Path $gitDir 'duo'
    New-Item -ItemType Directory -Path (Join-Path $duo 'logs') -Force | Out-Null
    return [pscustomobject]@{ Main = $main; Wt = $wt; GitDir = $gitDir; Duo = $duo }
}

function New-Commit($Repo, [string]$Subject, [string]$Trailer = '') {
    if ($Trailer) { Invoke-Git -C $Repo.Wt commit -q --allow-empty -m $Subject -m $Trailer | Out-Null }
    else { Invoke-Git -C $Repo.Wt commit -q --allow-empty -m $Subject | Out-Null }
    return Invoke-Git -C $Repo.Wt rev-parse HEAD
}

# Last line decides whether B is idle, as in a Cursor subagent transcript.
function New-Transcript($Repo, [bool]$Idle) {
    $path = Join-Path (Split-Path $Repo.Wt) 'transcript.jsonl'
    $text = '{"role":"user","message":{"content":[{"type":"text","text":"go"}]}}' + "`n"
    if ($Idle) { $text += '{"type":"turn_ended","status":"success"}' + "`n" }
    [IO.File]::WriteAllText($path, $text)
    return $path
}

function Set-Age([string]$Path, [int]$Minutes) {
    if (Test-Path -LiteralPath $Path) { (Get-Item -LiteralPath $Path).LastWriteTime = (Get-Date).AddMinutes(-$Minutes) }
}

# Make every file the watcher counts as a sign of life look 10 minutes old.
function Set-Quiet($Repo) {
    foreach ($p in @('index', 'HEAD', 'logs/HEAD')) { Set-Age (Join-Path $Repo.GitDir $p) 10 }
    Get-ChildItem -LiteralPath $Repo.Duo -File -Recurse | ForEach-Object { Set-Age $_.FullName 10 }
}

function Start-Watch($Repo, [string[]]$Extra) {
    $script:watchOut = Join-Path $Root "$Scenario.watch.out"
    $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Quote $watch), '-Worktree', (Quote $Repo.Wt), '-Tag', 't', '-PollSeconds', '1') + $Extra
    $script:t0 = Get-Date
    $script:watcher = Start-Process -FilePath $exe -ArgumentList $argv -RedirectStandardOutput $script:watchOut -RedirectStandardError "$($script:watchOut).err" -NoNewWindow -PassThru
}

function Get-Lines {
    if (Test-Path -LiteralPath $script:watchOut) { return @(Get-Content -LiteralPath $script:watchOut) }
    return @()
}

function Get-Wakes {
    return @(Get-Lines | Where-Object { $_ -match '^DUO_WAKE_t \d+ ' } | ForEach-Object { $_ -replace '^DUO_WAKE_t \d+ ', '' })
}

function Get-Elapsed { return ((Get-Date) - $script:t0).TotalSeconds }

# Returns the seconds since Start-Watch at which a line matching $Pattern was
# first seen, or -1 after $Seconds.
function Wait-Line([string]$Pattern, [int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        if (@(Get-Lines | Where-Object { $_ -match $Pattern }).Count) { return (Get-Elapsed) }
        Start-Sleep -Milliseconds 250
    }
    return -1
}

function Wait-Ready {
    $at = Wait-Line '^DUO_(READY|ERROR)_t ' 30
    $line = @(Get-Lines | Where-Object { $_ -match '^DUO_(READY|ERROR)_t ' }) | Select-Object -First 1
    Check ($at -ge 0 -and "$line" -like 'DUO_READY_t *') "watcher ready: $line"
    return "$line"
}

try {
    switch ($Scenario) {
        'not-git' {
            $dir = Join-Path $Root 'not-git'
            New-Item -ItemType Directory -Path $dir | Out-Null
            $ErrorActionPreference = 'Continue'
            $out = & $exe -NoProfile -ExecutionPolicy Bypass -File $watch -Worktree $dir -Tag t 2>&1
            $code = $LASTEXITCODE
            Check ("$out" -like 'DUO_ERROR_t not a git worktree*') "error line: $out"
            Check ($code -eq 1) "exit code 1 (got $code)"
        }
        'events' {
            $r = New-Worktree
            $h0 = Invoke-Git -C $r.Wt rev-parse HEAD
            Start-Watch $r @('-WatchStatus', '-HeartbeatMinutes', '1', '-StallMinutes', '1', '-StepMinutes', '1')
            $ready = Wait-Ready
            Check ($ready -match " head=$h0 requests=0 transcript=False ") 'ready line reports head, requests and no transcript'
            New-Commit $r 'wip' 'Flow: wip' | Out-Null
            Start-Sleep -Seconds 4
            Check ((Get-Wakes).Count -eq 0) 'Flow: wip commit does not wake'
            $s1 = New-Commit $r 's1' 'Flow: step S1'
            Check ((Wait-Line "^DUO_WAKE_t 1 commit $s1$" 15) -ge 0) 'Flow: step commit wakes'
            $s2 = New-Commit $r 'no trailer'
            Check ((Wait-Line "^DUO_WAKE_t 2 commit $s2$" 15) -ge 0) 'commit without Flow trailer wakes'
            [IO.File]::WriteAllText((Join-Path $r.Duo 'progress.md'), "STATUS: S0-DONE`n`n### R-1 question`n")
            Check ((Wait-Line '^DUO_WAKE_t 3 request 1$' 15) -ge 0) 'new ### R- heading wakes'
            Check ((Wait-Line '^DUO_WAKE_t 4 status STATUS: S0-DONE$' 15) -ge 0) 'STATUS: change wakes with -WatchStatus'
            $quietFrom = Get-Elapsed
            $hb = Wait-Line '^DUO_WAKE_t 5 heartbeat$' 100
            Check ($hb -ge 0 -and $hb - $quietFrom -ge 50) "heartbeat after a quiet minute (after $([int]($hb - $quietFrom))s)"
            Check (@(Get-Wakes | Where-Object { $_ -eq 'stall' }).Count -eq 0) 'no stall without a transcript'
            Check (@(Get-Wakes | Where-Object { $_ -like 'slow *' }).Count -eq 0) 'no slow without a transcript'
            for ($i = 0; $i -lt 10 -and (Test-Path -LiteralPath $r.GitDir); $i++) {
                $ErrorActionPreference = 'Continue'
                & git -C $r.Main worktree remove --force $r.Wt 2>&1 | Out-Null
                $ErrorActionPreference = 'Stop'
                if (Test-Path -LiteralPath $r.GitDir) { Start-Sleep -Seconds 1 }
            }
            Check ((Wait-Line '^DUO_EXIT_t worktree removed$' 20) -ge 0) 'DUO_EXIT when the worktree is removed'
            Check ($script:watcher.WaitForExit(10000)) 'watcher exits after DUO_EXIT'
        }
        'stall' {
            $r = New-Worktree
            $tr = New-Transcript $r $false
            Start-Watch $r @('-Transcript', (Quote $tr), '-StallMinutes', '1', '-HeartbeatMinutes', '1')
            $ready = Wait-Ready
            Check ($ready -match ' transcript=True ') 'ready line reports the transcript'
            Set-Quiet $r
            $at = Wait-Line '^DUO_WAKE_t \d+ stall$' 100
            Check ($at -ge 55) "stall after a silent minute (at $([int]$at)s)"
            Start-Sleep -Seconds 5
            $wakes = Get-Wakes
            Check ($wakes.Count -eq 1) "one stall, no heartbeat with a transcript: $($wakes -join ', ')"
        }
        'idle' {
            $r = New-Worktree
            $tr = New-Transcript $r $true
            Start-Watch $r @('-Transcript', (Quote $tr), '-StallMinutes', '1', '-HeartbeatMinutes', '1', '-StepMinutes', '1')
            Wait-Ready | Out-Null
            Set-Quiet $r
            Start-Sleep -Seconds 80
            $wakes = Get-Wakes
            Check ($wakes.Count -eq 0) "no wake while the transcript ends with turn_ended: $($wakes -join ', ')"
        }
        'running' {
            $r = New-Worktree
            $tr = New-Transcript $r $false
            $marker = Join-Path $r.Duo 'running'
            [IO.File]::WriteAllText($marker, "30`nslow test suite`n")
            Start-Watch $r @('-Transcript', (Quote $tr), '-StallMinutes', '1')
            Wait-Ready | Out-Null
            Set-Quiet $r
            Set-Age $marker 5
            Start-Sleep -Seconds 80
            $wakes = Get-Wakes
            Check ($wakes.Count -eq 0) "no stall while a running marker is within its expected minutes: $($wakes -join ', ')"
        }
        'edits' {
            $r = New-Worktree
            $tr = New-Transcript $r $false
            Start-Watch $r @('-Transcript', (Quote $tr), '-StallMinutes', '1')
            Wait-Ready | Out-Null
            Set-Quiet $r
            for ($i = 0; $i -lt 6; $i++) {
                [IO.File]::WriteAllText((Join-Path $r.Wt 'a.txt'), "edit $i`n")
                Start-Sleep -Seconds 15
            }
            $wakes = Get-Wakes
            Check ($wakes.Count -eq 0) "no stall while B edits tracked files: $($wakes -join ', ')"
        }
        'slow-repeat' {
            $r = New-Worktree
            $tr = New-Transcript $r $false
            [IO.File]::WriteAllText((Join-Path $r.Duo 'running'), "30`nslow test suite`n")
            Start-Watch $r @('-Transcript', (Quote $tr), '-StepMinutes', '1')
            Wait-Ready | Out-Null
            Start-Sleep -Seconds 30
            New-Commit $r 'wip' 'Flow: wip' | Out-Null
            $first = Wait-Line '^DUO_WAKE_t 1 slow 1$' 90
            Check ($first -ge 55 -and $first -lt 85) "slow 1 a minute after start, despite a running marker and a wip commit (at $([int]$first)s)"
            $second = Wait-Line '^DUO_WAKE_t 2 slow 2$' 90
            Check ($second -ge 115 -and $second -lt 145) "slow 2 one more minute later (at $([int]$second)s)"
        }
        'slow-step' {
            $r = New-Worktree
            $tr = New-Transcript $r $false
            Start-Watch $r @('-Transcript', (Quote $tr), '-StepMinutes', '1')
            Wait-Ready | Out-Null
            Check ((Wait-Line '^DUO_WAKE_t 1 slow 1$' 90) -ge 0) 'slow 1 before the step commit'
            $s1 = New-Commit $r 's1' 'Flow: step S1'
            $committed = Get-Elapsed
            Check ((Wait-Line "^DUO_WAKE_t 2 commit $s1$" 15) -ge 0) 'Flow: step commit wakes'
            $at = Wait-Line '^DUO_WAKE_t 3 slow 1$' 100
            $gap = $at - $committed
            Check ($at -ge 0 -and $gap -ge 55 -and $gap -lt 85) "a Flow: step commit restarts the timer and its minutes (slow 1 $([int]$gap)s after it): $((Get-Wakes) -join ', ')"
        }
        'slow-turn' {
            $r = New-Worktree
            $tr = New-Transcript $r $false
            Start-Watch $r @('-Transcript', (Quote $tr), '-StepMinutes', '1')
            Wait-Ready | Out-Null
            Check ((Wait-Line '^DUO_WAKE_t 1 slow 1$' 90) -ge 0) 'slow 1 during the first turn'
            [IO.File]::AppendAllText($tr, '{"type":"turn_ended","status":"success"}' + "`n")
            Start-Sleep -Seconds 70
            $wakes = Get-Wakes
            Check ($wakes.Count -eq 1) "no slow while B is idle: $($wakes -join ', ')"
            [IO.File]::AppendAllText($tr, '{"role":"user","message":{"content":[{"type":"text","text":"next"}]}}' + "`n")
            $resumed = Get-Elapsed
            $at = Wait-Line '^DUO_WAKE_t 2 slow 1$' 100
            $gap = $at - $resumed
            Check ($at -ge 0 -and $gap -ge 55 -and $gap -lt 85) "a new turn restarts the timer and its minutes (slow 1 $([int]$gap)s after it): $((Get-Wakes) -join ', ')"
        }
        default { Fail "unknown scenario" }
    }
}
catch {
    Fail "error: $($_.Exception.Message)"
}
finally {
    if ($script:watcher -and -not $script:watcher.HasExited) {
        Stop-Process -Id $script:watcher.Id -Force -ErrorAction SilentlyContinue
    }
    Say "DONE $Scenario"
}
