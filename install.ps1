# chatq one-line installer
#
#   iex (irm https://raw.githubusercontent.com/phal40lax78/chatq/main/install.ps1)
#
# Downloads chatq.ps1 to a real folder and dot-sources it from there. It has to
# reach disk first: chatq.ps1 finds data/ and the line it writes into $PROFILE
# from its own file path, and the background watcher it starts re-loads the file
# by that path - running it out of memory leaves all three empty.
#
# Under iex this runs in the caller's scope, which is the point - the dot-source
# at the end then lands the commands in the session you typed from. That also
# means it must not set $ErrorActionPreference or leave variables behind, and it
# cannot wrap itself in & { }, which would dot-source into a scope about to go.
#
# Set CHATQ_DIR beforehand to install somewhere other than ~/Tools/chatq.

$chatqUrl = 'https://raw.githubusercontent.com/phal40lax78/chatq/main/chatq.ps1'
$chatqDir = if ($env:CHATQ_DIR) { $env:CHATQ_DIR } else { Join-Path (Join-Path $HOME 'Tools') 'chatq' }
$chatqFile = Join-Path $chatqDir 'chatq.ps1'

# an untouched 5.1 may still default to TLS 1.0, which raw.githubusercontent
# refuses - add 1.2 rather than replacing whatever is already enabled
if ([Net.ServicePointManager]::SecurityProtocol -notmatch 'Tls12') {
    [Net.ServicePointManager]::SecurityProtocol =
    [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

New-Item -ItemType Directory -Path $chatqDir -Force -ErrorAction Stop | Out-Null
Write-Host "  downloading chatq.ps1 -> $chatqFile" -ForegroundColor DarkGray
Invoke-WebRequest $chatqUrl -OutFile $chatqFile -UseBasicParsing -ErrorAction Stop

. $chatqFile
chatqinstall

Remove-Variable chatqUrl, chatqDir, chatqFile -ErrorAction SilentlyContinue
