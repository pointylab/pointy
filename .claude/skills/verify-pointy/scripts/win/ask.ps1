# usage: ask.ps1 <card> <name> <question> [-Keep]
# Asks DSH in full mode from the card, through its page, and records every
# progress line it shows. With -Keep, closes the card while DSH works and
# follows the pill until the task is done. Touches only Pointy's windows.
param(
  [Parameter(Mandatory, Position = 0)][string]$Card,
  [Parameter(Mandatory, Position = 1)][string]$Name,
  [Parameter(Mandatory, Position = 2)][string]$Question,
  [switch]$Keep
)
. (Join-Path $PSScriptRoot 'env.ps1')

Js $Card 'window.__shown = []; const a = document.getElementById("activity"); new MutationObserver(() => { const t = a.innerText.trim(); if (t && window.__shown.at(-1) !== t) window.__shown.push(t) }).observe(a, { childList: true, subtree: true, characterData: true }); return "watching"' | Out-Null
$q = ConvertTo-Json -InputObject $Question -Compress
Js $Card "document.querySelector('#mode button[data-mode=deep]').click(); const i = document.getElementById('input'); i.value = $q; i.dispatchEvent(new Event('input')); document.getElementById('send').click(); return 'sent'" | Out-Null
Wait-Until 60 'a tool step in the card' {
  Js $Card 'if (!document.querySelector("#activity .step")) throw "no step yet"' 2>$null | Out-Null
  $true
}
Pa screenshot --window $Card (Join-Path $EV "$Name-progress.png") | Out-Null
Log "progress: $(Js $Card 'return document.getElementById("activity").innerText')"
if ($Keep) {
  Js $Card 'document.getElementById("close").click(); return "closed"' | Out-Null
  Wait-Until 10 'a pill' { Has-Page 'pill.html' }
  $pw = Win-Of 'pill.html'
  # Pills line up oldest first; an earlier card still finishing has one too.
  Log "pill while running: $(Js $pw 'return (p => (p.className + " | " + p.innerText + " | " + p.title).replace(/\s+/g, " "))([...document.querySelectorAll(".pill:not(.out)")].at(-1))')"
  Pa screenshot --window $pw (Join-Path $EV "$Name-pill-run.png") | Out-Null
  Wait-Until 60 'the pill to turn done' {
    Js $pw 'if (![...document.querySelectorAll(".pill:not(.out)")].at(-1).classList.contains("done")) throw "running"' 2>$null | Out-Null
    $true
  }
  Log "pill when done: $(Js $pw 'return (p => (p.className + " | " + p.innerText + " | " + p.title).replace(/\s+/g, " "))([...document.querySelectorAll(".pill:not(.out)")].at(-1))')"
  Pa screenshot --window $pw (Join-Path $EV "$Name-pill-done.png") | Out-Null
} else {
  Wait-Until 60 'the answer' {
    Js $Card 'if (document.getElementById("status").className !== "done") throw "running"' 2>$null | Out-Null
    $true
  }
  Pa screenshot --window $Card (Join-Path $EV "$Name-answer.png") | Out-Null
}
Log "card title: $(Js $Card 'return document.getElementById("title").textContent') | lines shown: $(Js $Card 'return window.__shown')"
