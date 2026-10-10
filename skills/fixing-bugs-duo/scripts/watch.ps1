param(
    [Parameter(Mandatory = $true)][string]$Worktree,
    [Parameter(Mandatory = $true)][string]$Tag,
    [string]$Transcript = '',
    [switch]$WatchStatus,
    [int]$PollSeconds = 15,
    [int]$HeartbeatMinutes = 20,
    [int]$StallMinutes = 10
)

# A is woken only by lines it matches, so a crash must say so on stdout.
trap {
    Write-Output "DUO_ERROR_$Tag $($_.Exception.Message)"
    exit 1
}

$gitDir = git --no-optional-locks -C $Worktree rev-parse --absolute-git-dir 2>$null
if ($LASTEXITCODE -ne 0 -or -not $gitDir) {
    Write-Output "DUO_ERROR_$Tag not a git worktree: $Worktree"
    exit 1
}
$gitDir = "$gitDir".Trim()
$duo = Join-Path $gitDir 'duo'
$progress = Join-Path $duo 'progress.md'
$running = Join-Path $duo 'running'
$seq = 0
$lastEvent = Get-Date

function Send-Wake([string]$Text) {
    $script:seq++
    Write-Output "DUO_WAKE_$Tag $($script:seq) $Text"
    $script:lastEvent = Get-Date
}

function Get-Head {
    $h = git --no-optional-locks -C $Worktree rev-parse HEAD 2>$null
    if ($LASTEXITCODE -eq 0) { return "$h".Trim() }
    return ''
}

# Wake only for commits A must look at now: Flow: step / fix, or no Flow trailer.
# wip, docs and anchored-adapt-only commits are picked up on the next wake.
function Test-NeedsReview([string]$From, [string]$To) {
    $shas = git --no-optional-locks -C $Worktree rev-list "$From..$To" 2>$null
    if ($LASTEXITCODE -ne 0) { return $true }
    foreach ($sha in @($shas)) {
        $body = (git --no-optional-locks -C $Worktree log -1 --format=%B $sha 2>$null) -join "`n"
        $flows = @([regex]::Matches($body, '(?m)^Flow:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value })
        if ($flows.Count -eq 0 -or ($flows -contains 'step') -or ($flows -contains 'fix')) { return $true }
    }
    return $false
}

function Get-RequestCount {
    if (-not (Test-Path -LiteralPath $progress)) { return 0 }
    return @(Select-String -LiteralPath $progress -Pattern '^### R-' -ErrorAction SilentlyContinue).Count
}

function Get-StatusLine {
    if (-not (Test-Path -LiteralPath $progress)) { return '' }
    $m = Select-String -LiteralPath $progress -Pattern '^STATUS:' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($m) { return $m.Line.Trim() }
    return ''
}

function Get-TranscriptState {
    if (-not $Transcript -or -not (Test-Path -LiteralPath $Transcript)) { return $null }
    $last = Get-Content -LiteralPath $Transcript -Tail 1 -ErrorAction SilentlyContinue
    return @{
        Length = (Get-Item -LiteralPath $Transcript).Length
        Idle   = ("$last" -match '"type"\s*:\s*"turn_ended"')
    }
}

function Test-Recent([string]$Path, [datetime]$Limit) {
    return (Test-Path -LiteralPath $Path) -and ((Get-Item -LiteralPath $Path).LastWriteTime -gt $Limit)
}

# Cursor writes a subagent transcript only when its turn ends, so a silent
# transcript proves nothing. Signs of life are the files B touches: a long
# command announced in duo/running (first line: expected minutes), anything
# else under duo/, and this worktree's index, HEAD and HEAD reflog.
function Test-OtherActivity([datetime]$Now) {
    if (Test-Path -LiteralPath $running) {
        $expected = 30
        $first = Get-Content -LiteralPath $running -TotalCount 1 -ErrorAction SilentlyContinue
        if ("$first" -match '^\s*(\d+)') { $expected = [int]$Matches[1] }
        $age = ($Now - (Get-Item -LiteralPath $running).LastWriteTime).TotalMinutes
        if ($age -lt ($expected + $StallMinutes)) { return $true }
    }
    $limit = $Now.AddMinutes(-$StallMinutes)
    $newest = Get-ChildItem -LiteralPath $duo -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($newest -and $newest.LastWriteTime -gt $limit) { return $true }
    foreach ($p in @('index', 'HEAD', 'logs/HEAD')) {
        if (Test-Recent (Join-Path $gitDir $p) $limit) { return $true }
    }
    return $false
}

# Costlier check, run only before reporting a stall: files B is editing.
function Test-WorktreeEdits([datetime]$Now) {
    $limit = $Now.AddMinutes(-$StallMinutes)
    $lines = git --no-optional-locks -C $Worktree status --porcelain -uall 2>$null
    foreach ($line in @($lines)) {
        if ("$line".Length -lt 4) { continue }
        $rel = ("$line".Substring(3) -replace '^.* -> ', '').Trim('"')
        if (Test-Recent (Join-Path $Worktree $rel) $limit) { return $true }
    }
    return $false
}

$head = Get-Head
$requests = Get-RequestCount
$status = Get-StatusLine
$ts = Get-TranscriptState
$tsLength = if ($ts) { $ts.Length } else { -1 }
$activeAt = Get-Date
$stallReported = $false
Write-Output "DUO_READY_$Tag pid=$PID head=$head requests=$requests transcript=$([bool]$ts) duo=$duo"

while ($true) {
    Start-Sleep -Seconds $PollSeconds
    $now = Get-Date
    if (-not (Test-Path -LiteralPath $gitDir)) {
        Write-Output "DUO_EXIT_$Tag worktree removed"
        exit 0
    }

    $h = Get-Head
    if ($h -and $h -ne $head) {
        if (-not $head -or (Test-NeedsReview $head $h)) { Send-Wake "commit $h" }
        $head = $h
    }

    $r = Get-RequestCount
    if ($r -ne $requests) {
        $requests = $r
        Send-Wake "request $r"
    }

    if ($WatchStatus) {
        $s = Get-StatusLine
        if ($s -ne $status) {
            $status = $s
            if ($s) { Send-Wake "status $s" }
        }
    }

    $idle = $false
    $ts = Get-TranscriptState
    if ($ts) {
        $idle = $ts.Idle
        # Test-OtherActivity looks back StallMinutes, so when it is false the
        # silence already lasted that long; activeAt only tracks the transcript.
        if ($ts.Length -ne $tsLength) {
            $tsLength = $ts.Length
            $activeAt = $now
            $stallReported = $false
        }
        if (Test-OtherActivity $now) {
            $stallReported = $false
        }
        elseif (-not $idle -and -not $stallReported -and ($now - $activeAt).TotalMinutes -ge $StallMinutes) {
            if (-not (Test-WorktreeEdits $now)) {
                $stallReported = $true
                Send-Wake 'stall'
            }
        }
    }
    # With a transcript, silence is already reported as stall; heartbeat is only for runs without one.
    if ($idle -or $ts) {
        $lastEvent = $now
    }
    elseif (($now - $lastEvent).TotalMinutes -ge $HeartbeatMinutes) {
        Send-Wake 'heartbeat'
    }
}
