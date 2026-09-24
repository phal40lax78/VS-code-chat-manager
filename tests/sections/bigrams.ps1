# tests/sections/bigrams.ps1: dot-sourced by tests/run-tests.ps1 in its turn,
# never on its own - it uses what the runner and the sections before it set.

Section 'bigrams and cosine'
$a = Get-ChatqBigrams 'card UI redesign'
Check 'identical text scores 1' ([Math]::Abs((Get-ChatqCosine $a (Get-ChatqBigrams 'card UI redesign')) - 1) -lt 1e-9)
Check 'disjoint text scores 0' ((Get-ChatqCosine $a (Get-ChatqBigrams 'zzz qqq')) -eq 0)
$h = Get-ChatqCosine (Get-ChatqBigrams "$tSel $tTong") (Get-ChatqBigrams "$tTong card")
Check 'shared Hangul word scores above 0' ($h -gt 0) $h
Check 'Hangul syllables count as letters' ((Get-ChatqBigrams $tSel).Count -eq 3) (Get-ChatqBigrams $tSel).Count
Check 'empty input scores 0, no throw' ((Get-ChatqCosine (Get-ChatqBigrams '') $a) -eq 0)
