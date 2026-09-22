# Fake claude / codex for tests/run-tests.ps1. Driven by environment variables:
#   FAKE_RECORD    folder: writes stdin.bin (raw bytes), argv.txt, env.txt
#   FAKE_SCENARIO  a .jsonl to replay on stdout, {{RESETS}} / {{SESSION}}
#                  replaced; absent means a plain success
#   FAKE_LAND      a transcript to append the prompt to as a user record, the
#                  way a real run does before the limit cuts it off
#   FAKE_STDERR    bytes of noise to write to stderr first (pipe-deadlock test)
#   FAKE_SLEEP     seconds to hang before answering (timeout test)
#   FAKE_AGENTS    what `claude agents --json` prints (live chats)
#   FAKE_ARCHIVE_FAIL  make `codex archive` / `unarchive` fail
# Output goes out as raw UTF-8 bytes: Write-Output would encode it in the
# console code page, which is exactly the bug class these tests exist for.

$ErrorActionPreference = 'Stop'
# fake-claude.cmd hands the command line over as one string; split it the way
# the MSVCRT does for what chatq sends - quoted runs, \" inside them - which
# keeps "" (an empty argument) and a lone - intact
$argv = @([regex]::Matches([string]$env:FAKE_ARGV, '"((?:\\"|[^"])*)"|(\S+)') | ForEach-Object {
        if ($_.Groups[1].Success) { $_.Groups[1].Value.Replace('\"', '"') } else { $_.Groups[2].Value }
    })
$in = [Console]::OpenStandardInput()
$ms = New-Object System.IO.MemoryStream
$in.CopyTo($ms)
$bytes = $ms.ToArray()
$utf8 = New-Object System.Text.UTF8Encoding $false
$prompt = $utf8.GetString($bytes)

if ($argv.Count -and $argv[0] -in 'archive', 'unarchive') {
    # codex archive / unarchive <id>: the rollout moves between sessions/ and
    # archived_sessions/ under CODEX_HOME, keeping its dated sub-path
    $home2 = $env:CODEX_HOME
    $from = if ($argv[0] -eq 'archive') { 'sessions' } else { 'archived_sessions' }
    $to = if ($argv[0] -eq 'archive') { 'archived_sessions' } else { 'sessions' }
    $root = Join-Path $home2 $from
    $f = @(Get-ChildItem -LiteralPath $root -Filter "*$($argv[1])*.jsonl" -File -Recurse -EA SilentlyContinue) | Select-Object -First 1
    if (-not $f -or $env:FAKE_ARCHIVE_FAIL) {
        $e = [Console]::OpenStandardError()
        $b = $utf8.GetBytes("Error: no session found for $($argv[1])`n")
        $e.Write($b, 0, $b.Length); $e.Flush()
        exit 1
    }
    $rel = $f.FullName.Substring($root.Length).TrimStart('\', '/')
    $dest = Join-Path (Join-Path $home2 $to) $rel
    New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null
    Move-Item -LiteralPath $f.FullName -Destination $dest -Force
    exit 0
}

if ($argv.Count -and $argv[0] -eq 'agents') {
    # claude agents --json: FAKE_AGENTS, or nobody live
    $o = [Console]::OpenStandardOutput()
    $b = $utf8.GetBytes($(if ($env:FAKE_AGENTS) { $env:FAKE_AGENTS } else { '[]' }) + "`n")
    $o.Write($b, 0, $b.Length); $o.Flush()
    exit 0
}

if ($env:FAKE_RECORD) {
    New-Item -ItemType Directory -Path $env:FAKE_RECORD -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $env:FAKE_RECORD 'pid.txt'), "$PID", $utf8)
    [IO.File]::WriteAllBytes((Join-Path $env:FAKE_RECORD 'stdin.bin'), $bytes)
    [IO.File]::WriteAllText((Join-Path $env:FAKE_RECORD 'argv.txt'), ($argv -join "`n"), $utf8)
    $seen = @('ANTHROPIC_API_KEY', 'CLAUDECODE', 'CLAUDE_CODE_SESSION_ID', 'CLAUDE_CONFIG_DIR') | ForEach-Object {
        "$_=$([Environment]::GetEnvironmentVariable($_))"
    }
    [IO.File]::WriteAllText((Join-Path $env:FAKE_RECORD 'env.txt'), ($seen -join "`n"), $utf8)
}

if ($argv -contains '--version') {
    $o = [Console]::OpenStandardOutput()
    $b = $utf8.GetBytes("2.1.278 (Claude Code)`n")
    $o.Write($b, 0, $b.Length); $o.Flush()
    exit 0
}

if ($env:FAKE_STDERR) {
    $e = [Console]::OpenStandardError()
    $junk = $utf8.GetBytes(('x' * 1023) + "`n")
    for ($i = 0; $i -lt [int]$env:FAKE_STDERR / 1024; $i++) { $e.Write($junk, 0, $junk.Length) }
    $e.Flush()
}
if ($env:FAKE_SLEEP) { Start-Sleep -Seconds ([int]$env:FAKE_SLEEP) }

$session = '00000000-0000-4000-8000-000000000000'
$i = [Array]::IndexOf($argv, '--resume')
if ($i -ge 0 -and $i + 1 -lt $argv.Count) { $session = $argv[$i + 1] }

if ($env:FAKE_LAND -and (Test-Path -LiteralPath $env:FAKE_LAND)) {
    $rec = [ordered]@{
        type = 'user'; message = @{ role = 'user'; content = $prompt }
        uuid = [guid]::NewGuid().ToString(); timestamp = (Get-Date).ToUniversalTime().ToString('o')
        sessionId = $session
    } | ConvertTo-Json -Compress -Depth 5
    [IO.File]::AppendAllText($env:FAKE_LAND, $rec + "`n", $utf8)
}

$lines = if ($env:FAKE_SCENARIO) { [IO.File]::ReadAllLines($env:FAKE_SCENARIO, $utf8) } else {
    @(
        '{"type":"system","subtype":"init","session_id":"{{SESSION}}","model":"claude-fake-1","permissionMode":"default","claude_code_version":"2.1.278"}'
        '{"type":"assistant","message":{"model":"claude-fake-1","role":"assistant","content":[{"type":"text","text":"ok"}]}}'
        '{"is_error":false,"num_turns":1,"subtype":"success","result":"ok","session_id":"{{SESSION}}","permission_denials":[],"type":"result"}'
    )
}
$resets = [DateTimeOffset]::UtcNow.AddHours(2).ToUnixTimeSeconds()
$out = [Console]::OpenStandardOutput()
foreach ($l in $lines) {
    if (-not $l.Trim()) { continue }
    $t = $l.Replace('{{RESETS}}', "$resets").Replace('{{SESSION}}', $session)
    $b = $utf8.GetBytes($t + "`n")
    $out.Write($b, 0, $b.Length)
}
$out.Flush()
exit 0
