param([int]$DolphinProcessId = 0, [switch]$LiveSplit, [int]$Port = 16834, [int]$MaxMinutes = 0)
$ErrorActionPreference = 'Stop'
$session = Join-Path $PSScriptRoot ('HKRR-prototype-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,6))
$null = New-Item -ItemType Directory -Path $session
$reader = $null
$csv = $null
$marks = $null
$failed = $false
$ls = $null
$events = $null
$owned = $false
$homeArmed = $false
$successArmed = $false
$previousActive = $false
$gameTimePaused = $null
$timerPhase = 'NotRunning'
$rules = Get-Content (Join-Path $PSScriptRoot 'timing-rules.json') -Raw | ConvertFrom-Json
function Test-Active([uint32[]]$values) {
    foreach ($condition in $rules.active_conditions) {
        $value = $values[[int]$condition.index]
        if ($condition.operator -eq 'eq' -and $value -ne $condition.value) { return $false }
        if ($condition.operator -eq 'ne' -and $value -eq $condition.value) { return $false }
    }
    return $true
}
function Send-Action([string]$command, [long]$time) {
    $events.WriteLine(('{0},{1}' -f $time,$command))
    $events.Flush()
    Write-Host ('{0,8} ms | {1}' -f $time,$command) -ForegroundColor Cyan
    if ($null -ne $ls) { $ls.Send($command) }
}
try {
    if ($MaxMinutes -lt 0 -or $Port -lt 1 -or $Port -gt 65535) { throw 'Nieprawidlowy limit lub port.' }
    if (-not [Environment]::Is64BitProcess) { throw 'Wymagany 64-bitowy Windows PowerShell.' }
    if (-not ('HKMemoryReader' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'MemoryReader.cs') }
    Write-Host 'HKRR prototyp v0.3 - start po loadingu, split na Mission Clear.'
    if ($LiveSplit) { Write-Host 'TRYB LIVESPLIT: prototyp bedzie sterowac timerem. Uzyj kopii splitow.' }
    else { Write-Host 'TRYB PODGLADU: pokazuje polecenia, ale nie steruje LiveSplitem.' }
    Write-Host 'Uruchom gre i wstrzymaj Dolphin przez Pause, nie Stop.'
    $null = Read-Host 'Enter, gdy gotowe'
    if ($DolphinProcessId -gt 0) {
        $target = Get-Process -Id $DolphinProcessId
        if ($target.ProcessName -ne 'Dolphin') { throw 'Wybrany proces nie jest Dolphin.exe.' }
    } else {
        $targets = @(Get-Process -Name Dolphin -ErrorAction SilentlyContinue)
        if ($targets.Count -ne 1) { throw 'Uruchom dokladnie jeden Dolphin.exe.' }
        $target = $targets[0]
    }
    $reader = New-Object HKMemoryReader($target.Id)
    if ($reader.GameId -ne 'GH6EAF' -or $reader.Revision -ne 0) { throw 'Ta wersja obsluguje tylko GH6EAF, rewizja 0.' }
    $csv = New-Object IO.StreamWriter((Join-Path $session 'states.csv'), $false, [Text.Encoding]::UTF8)
    $marks = New-Object IO.StreamWriter((Join-Path $session 'markers.csv'), $false, [Text.Encoding]::UTF8)
    $csv.WriteLine('elapsed_ms,read_ms,pointer,state0,state4,state8,stateC,state10,state14,state18,state1C')
    $marks.WriteLine('elapsed_ms,marker')
    $events = New-Object IO.StreamWriter((Join-Path $session 'events.csv'), $false, [Text.Encoding]::UTF8)
    $events.WriteLine('elapsed_ms,command')
    if ($LiveSplit) {
        if (-not ('HKLiveSplitClient' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'LiveSplitClient.cs') }
        $ls = New-Object HKLiveSplitClient($Port)
        if ($ls.Query('ping') -ne 'pong') { throw 'Serwer nie odpowiada jak LiveSplit.' }
        $timerPhase = $ls.Query('getcurrenttimerphase')
        if ($timerPhase -ne 'NotRunning') { throw 'Uruchom prototyp przy zresetowanym timerze LiveSplita.' }
    }
    [ordered]@{
        tool_version='0.3'; game_id=$reader.GameId; revision=$reader.Revision;
        actual_emulator_version=$target.MainModule.FileVersionInfo.FileVersion;
        reported_emulator_version='Dolphin 2609a';
        start_utc=[DateTime]::UtcNow.ToString('o'); poll_target_ms=20;
        pointer_address='0x802CEFB4'; state_offsets='0,4,8,C,10,14,18,1C';
        host_base=('0x{0:X}' -f $reader.BaseAddress);
        timing='Wall clock, includes Dolphin pauses; this is a diagnostic log, not run timing';
        livesplit_enabled=[bool]$LiveSplit; max_minutes=$MaxMinutes; timing_rules=$rules;
        observations='Candidate meanings only: state0 3=home,4=mission,10=clear; state4 18=failed in uploaded session';
    } | ConvertTo-Json | Set-Content (Join-Path $session 'manifest.json') -Encoding UTF8
    $labels=@{'H'='home';'M'='mission_select';'D'='door_dialog';'B'='mission_confirm';'C'='first_control';'S'='mission_clear';'F'='mission_failed';'R'='retry';'P'='dolphin_pause';'L'='loading';'T'='title'}
    Write-Host 'Wroc do Dolphina, wznow emulacje i graj NORMALNIE, bez pauz do zapisu.'
    Write-Host 'Skrypt zapisuje automatycznie. Q w tym oknie konczy i tworzy ZIP.'
    Write-Host 'Brak limitu czasu w ustawieniach domyslnych. Przed runem zacznij w domu.'
    Write-Host 'Opcjonalne znaczniki w tym oknie: H dom, D drzwi, M mapa, C sterowanie, S sukces, F porazka, R retry, P pauza.'
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $previous=''
    $lastFlush=0
    $lastHeader=0
    $lastPhaseCheck=-1000
    $lastStatus=0
    $rows=0
    while ($true) {
        $begin=$clock.ElapsedMilliseconds
        if ([Console]::KeyAvailable) {
            $key=[Console]::ReadKey($true).KeyChar.ToString().ToUpperInvariant()
            if ($key -eq 'Q') { break }
            if ($labels.ContainsKey($key)) { $marks.WriteLine(('{0},{1}' -f $begin,$labels[$key])); $marks.Flush() }
        }
        if ($begin - $lastHeader -ge 1000) {
            # Decimal value avoids signed hexadecimal parsing in Windows PowerShell 5.1.
            $header=$reader.ReadGuest([uint32]2147483648,32)
            if ([Text.Encoding]::ASCII.GetString($header,0,6) -ne 'GH6EAF' -or $header[7] -ne 0 -or
                $header[28] -ne 194 -or $header[29] -ne 51 -or $header[30] -ne 159 -or $header[31] -ne 61) {
                throw 'Gra lub mapowanie pamieci ulegly zmianie. Rozpocznij nowa sesje.'
            }
            $lastHeader=$begin
        }
        $values=$reader.ReadState()
        $duration=$clock.ElapsedMilliseconds-$begin
        $line=('{0},{1},{2}' -f $begin,$duration,($values -join ','))
        $csv.WriteLine($line)
        $rows++
        $active = Test-Active $values
        if ($null -ne $ls -and $begin-$lastPhaseCheck -ge 250) {
            $newPhase=$ls.Query('getcurrenttimerphase')
            if ($newPhase -notin @('NotRunning','Running','Paused','Ended')) { throw 'Nieznana odpowiedz fazy timera.' }
            if ($owned -and $newPhase -in @('NotRunning','Ended')) {
                $owned=$false; $homeArmed=$false; $successArmed=$false; $gameTimePaused=$null
            }
            $timerPhase=$newPhase
            $lastPhaseCheck=$begin
        }
        if (-not $owned -and $timerPhase -eq 'NotRunning' -and $values[1] -eq $rules.home_state) { $homeArmed=$true }
        # Attaching in an already-loaded mission cannot auto-start a run.
        if ($active -and -not $previousActive -and -not $owned -and $homeArmed -and $timerPhase -eq 'NotRunning') {
            Send-Action 'starttimer' $begin
            Send-Action 'setgametime 0' $begin
            Send-Action 'switchto gametime' $begin
            $owned=$true; $homeArmed=$false; $timerPhase='Running'; $gameTimePaused=$null
            if ($null -ne $ls -and $ls.Query('getcurrenttimerphase') -ne 'Running') { throw 'LiveSplit nie rozpoczal proby.' }
        }
        if ($owned) {
            if ($active -and -not $previousActive) { $successArmed=$true }
            if ($values[2] -eq $rules.failure_value -or $values[5] -eq $rules.failure_value) { $successArmed=$false }
            if ($timerPhase -eq 'Running') {
                $desiredPause=-not $active
                if ($null -eq $gameTimePaused -or $desiredPause -ne $gameTimePaused) {
                    if ($desiredPause) { Send-Action 'pausegametime' $begin }
                    else { Send-Action 'unpausegametime' $begin }
                    $gameTimePaused=$desiredPause
                }
                if ($values[1] -eq $rules.clear_state -and $successArmed) {
                    Send-Action 'split' $begin
                    $successArmed=$false
                }
            }
        }
        $previousActive=$active
        $signature=($values -join ',')
        if ($signature -ne $previous) {
            Write-Host ('{0,8} ms | stan={1}, pole4={2}, pole10={3}, pole14={4}' -f $begin,$values[1],$values[2],$values[5],$values[6])
            $previous=$signature
        }
        if ($begin-$lastFlush -ge 1000) { $csv.Flush(); $lastFlush=$begin }
        if ($MaxMinutes -gt 0 -and $begin -ge $MaxMinutes*60000) { Write-Host 'Osiagnieto wybrany limit.'; break }
        if ($begin-$lastStatus -ge 600000) { Write-Host 'Zapis trwa. Q w tym oknie konczy i pakuje wyniki.'; $lastStatus=$begin }
        $delay=20-($clock.ElapsedMilliseconds-$begin)
        if ($delay -gt 0) { Start-Sleep -Milliseconds ([int]$delay) }
    }
    ('Completed. Rows: ' + $rows) | Set-Content (Join-Path $session 'diagnostic.txt') -Encoding UTF8
} catch {
    $failed=$true
    $_.Exception.ToString() | Set-Content (Join-Path $session 'diagnostic.txt') -Encoding UTF8
    Write-Host ('BLAD: ' + $_.Exception.Message) -ForegroundColor Red
} finally {
    if ($null -ne $ls) {
        if ($owned) { try { $ls.Send('pausegametime') } catch { Write-Host 'Nie mozna wstrzymac Game Time. Sprawdz timer recznie.' } }
        $ls.Dispose()
    }
    if ($null -ne $events) { $events.Dispose() }
    if ($null -ne $csv) { $csv.Dispose() }
    if ($null -ne $marks) { $marks.Dispose() }
    if ($null -ne $reader) { $reader.Dispose() }
    try {
        $archive=$session+'.zip'
        Compress-Archive -Path (Join-Path $session '*') -DestinationPath $archive
        Write-Host ('Przeslij ZIP: ' + $archive)
    } catch { $failed=$true; Write-Host ('Nie udalo sie spakowac. Zachowaj folder: ' + $session) }
}
if ($failed) { exit 1 }
