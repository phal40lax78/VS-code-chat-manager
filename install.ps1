# VS-code-chat-manager one-line installer
#
#   iex (irm https://raw.githubusercontent.com/phal40lax78/VS-code-chat-manager/main/install.ps1)
#
# Downloads VS-code-chat-manager.ps1 to a real folder and dot-sources it from
# there. It has to reach disk first: the script finds data/ and the line it
# writes into $PROFILE from its own file path, and the background watcher it
# starts re-loads the file by that path - running it out of memory leaves all
# three empty.
#
# Under iex this runs in the caller's scope, which is the point - the dot-source
# at the end then lands the commands in the session you typed from. That also
# means it must not set $ErrorActionPreference or leave variables behind, and it
# cannot wrap itself in & { }, which would dot-source into a scope about to go.
#
# Set CHAT_MANAGER_DIR beforehand to install somewhere other than
# ~/Tools/VS-code-chat-manager.

$chatManagerUrl = 'https://raw.githubusercontent.com/phal40lax78/VS-code-chat-manager/main/VS-code-chat-manager.ps1'
$chatManagerDir = if ($env:CHAT_MANAGER_DIR) { $env:CHAT_MANAGER_DIR } else { Join-Path (Join-Path $HOME 'Tools') 'VS-code-chat-manager' }
$chatManagerFile = Join-Path $chatManagerDir 'VS-code-chat-manager.ps1'

# an untouched 5.1 may still default to TLS 1.0, which raw.githubusercontent
# refuses - add 1.2 rather than replacing whatever is already enabled
if ([Net.ServicePointManager]::SecurityProtocol -notmatch 'Tls12') {
    [Net.ServicePointManager]::SecurityProtocol =
    [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

New-Item -ItemType Directory -Path $chatManagerDir -Force -ErrorAction Stop | Out-Null
Write-Host "  downloading VS-code-chat-manager.ps1 -> $chatManagerFile" -ForegroundColor DarkGray
Invoke-WebRequest $chatManagerUrl -OutFile $chatManagerFile -UseBasicParsing -ErrorAction Stop

. $chatManagerFile
chatqinstall

Remove-Variable chatManagerUrl, chatManagerDir, chatManagerFile -ErrorAction SilentlyContinue
