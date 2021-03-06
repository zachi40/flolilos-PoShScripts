#requires -version 3

<#
    .SYNOPSIS
        Prevents idle-standby while CPU is working or while specified processes are running.
    .DESCRIPTION
        Will simulate F15-key-press to prevent computer from entering standby. 
    .NOTES
        Version:    2.0
        Author:     flolilo
        Date:       2017-09-16
        Legal stuff: This program is free software. It comes without any warranty, to the extent permitted by
        applicable law. Most of the script was written by myself (or heavily modified by me when searching for solutions
        on the WWW). However, some parts are copies or modifications of very genuine code - see
        the "CREDIT"-tags to find them.

    .PARAMETER Mode
        Valid options:
            "process"   - Script will close after certain process(es) are finished.
            "cpu"       - Script will close when CPU-usage is no longer above the specified threshold
            "none"      - Script will run forever.
    .PARAMETER Process
        Specifies processes that the user wants the script to watch for.
    .PARAMETER CPUthresh
        Specifies threshold of CPU-usage that the script should watch for.
    .PARAMETER TimeBase
        Value of time (in seconds) that has to pass between to iterations of the script - different steps of the script will use TimeBase/2 and TimeBase/10 as their values, too.
    .PARAMETER CounterMax
        Maximum time of iterations between criteria for closing the script are met and the atual closing of the script.
    .PARAMETER Shutdown
        Value of 1 will initiate shutdown of computer after finishing the script.

    .INPUTS
        None.
    .OUTPUTS
        None.

    .EXAMPLE
        Run forever:
        preventsleep.ps1 -Mode "none"
    .EXAMPLE
        Run until CPU usage falls below 90%, don't shut down afterwards:
        preventsleep.ps1 -Mode "cpu" -CPUthresh 90 -Shutdown 0
    .EXAMPLE
        Check if robocopy is runnning and shut down afterwards:
        preventsleep.ps1 -Mode "process" -Process "robocopy" -Shutdown 1
#>
param(
    [string]$Mode = "specify",
    [array]$Process = @(),
    [int]$CPUthresh = 0,

    [ValidateRange(10,3600)]
    [int]$TimeBase = 90,

    [ValidateRange(1,100)]
    [int]$CounterMax = 10,

    [int]$Shutdown = -1
)

# DEFINITION: Get all error-outputs in English:
    [Threading.Thread]::CurrentThread.CurrentUICulture = 'en-US'
# DEFINITION: Hopefully avoiding errors by wrong encoding now:
    $OutputEncoding = New-Object -TypeName System.Text.UTF8Encoding
    [Console]::InputEncoding = New-Object -TypeName System.Text.UTF8Encoding


# ==================================================================================================
# ==============================================================================
#    Defining generic functions:
# ==============================================================================
# ==================================================================================================

# DEFINITION: Making Write-Host much, much faster:
Function Write-ColorOut(){
    <#
        .SYNOPSIS
            A faster version of Write-Host
        .DESCRIPTION
            Using the [Console]-commands to make everything faster.
        .NOTES
            Date: 2018-05-22
        
        .PARAMETER Object
            String to write out
        .PARAMETER ForegroundColor
            Color of characters. If not specified, uses color that was set before calling. Valid: White (PS-Default), Red, Yellow, Cyan, Green, Gray, Magenta, Blue, Black, DarkRed, DarkYellow, DarkCyan, DarkGreen, DarkGray, DarkMagenta, DarkBlue
        .PARAMETER BackgroundColor
            Color of background. If not specified, uses color that was set before calling. Valid: DarkMagenta (PS-Default), White, Red, Yellow, Cyan, Green, Gray, Magenta, Blue, Black, DarkRed, DarkYellow, DarkCyan, DarkGreen, DarkGray, DarkBlue
        .PARAMETER NoNewLine
            When enabled, no line-break will be created.

        .EXAMPLE
            Just use it like Write-Host.
    #>
    param(
        [string]$Object = "Write-ColorOut was called, but no string was transfered.",

        [ValidateSet("DarkBlue","DarkGreen","DarkCyan","DarkRed","Blue","Green","Cyan","Red","Magenta","Yellow","Black","DarkGray","Gray","DarkYellow","White","DarkMagenta")]
        [string]$ForegroundColor,

        [ValidateSet("DarkBlue","DarkGreen","DarkCyan","DarkRed","Blue","Green","Cyan","Red","Magenta","Yellow","Black","DarkGray","Gray","DarkYellow","White","DarkMagenta")]
        [string]$BackgroundColor,

        [switch]$NoNewLine=$false,

        [ValidateRange(0,48)]
        [int]$Indentation=0
    )

    if($ForegroundColor.Length -ge 3){
        $old_fg_color = [Console]::ForegroundColor
        [Console]::ForegroundColor = $ForegroundColor
    }
    if($BackgroundColor.Length -ge 3){
        $old_bg_color = [Console]::BackgroundColor
        [Console]::BackgroundColor = $BackgroundColor
    }
    if($Indentation -gt 0){
        [Console]::CursorLeft = $Indentation
    }

    if($NoNewLine -eq $false){
        [Console]::WriteLine($Object)
    }else{
        [Console]::Write($Object)
    }
    
    if($ForegroundColor.Length -ge 3){
        [Console]::ForegroundColor = $old_fg_color
    }
    if($BackgroundColor.Length -ge 3){
        [Console]::BackgroundColor = $old_bg_color
    }
}


# ==================================================================================================
# ==============================================================================
#    Defining specific functions:
# ==============================================================================
# ==================================================================================================

# DEFINITION: Get variables if not properly specified:
Function Get-UserVars(){
    if($script:Mode -ne "process" -and $script:Mode -ne "cpu" -and $script:Mode -ne "none"){
        Write-ColorOut "Which condition should end the script? // Welche Bedingung soll das Skript beenden?" -ForegroundColor Gray -Indentation 4
        Write-ColorOut "`"cpu`"`t=`tCPU-usage falls below specified threshold. // CPU-Nutzung faellt unter angegebenes Limit." -ForegroundColor DarkGray -Indentation 4
        Write-ColorOut "`"process`"`t=`tSpecified process is no longer running. // Angegebener Prozess laeuft nicht mehr." -ForegroundColor DarkGray -Indentation 4
        Write-ColorOut "`"none`"`t=`tEndless action. // Laeuft ewig." -ForegroundColor DarkGray -Indentation 4
        while($true){
            [string]$script:Mode = Read-Host "    Enter mode: // Modus eingeben:`t"
            if($script:Mode -eq "cpu" -or $script:Mode -eq "process" -or $script:Mode -eq "none"){
                break
            }else{
                Write-ColorOut "Invalid choice, please try again. // Ungueltige Angabe, bitte erneut versuchen." -ForegroundColor Magenta -Indentation 4
                continue
            }
        }
    }

    if($script:Mode -eq "cpu"){
        if($CPUthresh -notin (2..99)){
            while($true){
                Write-ColorOut "Enter the CPU-threshold in %. (enter w/o %-sign) - Recommendation: 90% // Grenzwert der CPU-Auslastung in % angeben. (Angabe ohne %-Zeichen) Empfehlung: 90%`t" -ForegroundColor Gray -NoNewLine
                [int]$script:CPUthresh = Read-Host
                if($script:CPUthresh -in (2..99)){
                    break
                }else{
                    Write-ColorOut "Invalid choice, please try again. // Ungueltige Angabe, bitte erneut versuchen." -ForegroundColor Magenta -Indentation 4
                    continue
                }
            }
        }
    }elseif($script:Mode -eq "process"){
        if($script:Process.Length -lt 1){
            while($true){
                Write-ColorOut "How many Processes? // Wieviele Prozesse?`t" -ForegroundColor Gray -NoNewLine
                [int]$processCount = Read-Host
                if($processCount -in (1..100)){
                    break
                }else{
                    Write-ColorOut "Invalid choice, please try again. // Ungueltige Angabe, bitte erneut versuchen." -ForegroundColor Magenta -Indentation 4
                    continue
                }
            }
            for($i=0; $i -lt $processCount; $i++){
                Write-ColorOut "Please specify name of process # $($i + 1): // Bitte Namen von Prozess # $($i + 1) eingeben:`t" -ForegroundColor Gray -NoNewline -Indentation 4
                [array]$script:Process += Read-Host 
            }
        }
        if("powershell" -in $script:Process){
            [int]$script:PoShCompensation = 1
        }else{
            [int]$script:PoShCompensation = 0
        }
    }

    if($script:Mode -ne "none" -and $script:Shutdown -notin (0..1)){
        while($true){
            Write-ColorOut "Shutdown when done? `"1`" for yes, `"0`" for no: // Nach Abschluss herunterfahren? `"1`" fuer Ja, `"0`" fuer Nein:`t" -ForegroundColor Gray -NoNewLine
            [int]$script:Shutdown = Read-Host
            if($script:Shutdown -in (0..1)){
                break
            }else{
                Write-ColorOut "Invalid choice, please try again. // Ungueltige Angabe, bitte erneut versuchen." -ForegroundColor Magenta -Indentation 4
                continue
            }
        }
    }
}

# DEFINITION: Get Average CPU-usage:
Function Get-ComputerStats(){
    [array]$cpu = @()
    for($i = 0; $i -lt 3; $i++){
        $cpu += (Get-Counter "\Processor(_total)\% Processor Time").countersamples.cookedvalue
        Start-Sleep -Seconds 1
        [int]$value = [math]::ceiling(($cpu | Measure-Object -Average | Select-Object -ExpandProperty Average))
    }
    return $value
}

# DEFINITION: Iteration to prevent standby:
Function Start-Preventing(){
    # DEFINITION: For button-emulation:
    $myShell = New-Object -com "Wscript.Shell"

    [int]$counter = 0
    while($counter -lt $script:CounterMax){
        $myShell.sendkeys("{F15}")
        
        if($script:Mode -eq "none"){
            Write-ColorOut "$(Get-Date -Format 'dd.MM.yy, HH:mm:ss')" -NoNewline
            Write-ColorOut " - Running forever, sleeping for $script:TimeBase seconds. // Laufe fuer immer, schlafe $script:TimeBase Sekunden." -ForegroundColor DarkGray
            Start-Sleep -Seconds $script:TimeBase
        }elseif($script:Mode -eq "process"){
            $activeProcessCounter = @(Get-Process -ErrorAction SilentlyContinue -Name $script:Process).count - $script:PoShCompensation
            if($activeProcessCounter -gt 0){
                Write-ColorOut "$(Get-Date -Format 'dd.MM.yy, HH:mm:ss')" -NoNewline
                Write-ColorOut " - Process(es) `"$script:Process`" not yet done, sleeping for $script:TimeBase seconds. // Prozess(e) `"$script:Process`" noch nicht fertig, schlafe $script:TimeBase Sekunden." -ForegroundColor DarkGray
                $counter = 0
                Start-Sleep -Seconds $script:TimeBase
            }Else{
                Write-ColorOut "$(Get-Date -Format 'dd.MM.yy, HH:mm:ss')" -NoNewline
                Write-ColorOut " - Process(es) `"$script:Process`" done, sleeping for $([math]::ceiling(($script:TimeBase / 2))) seconds. // Prozess(e) `"$script:Process`" fertig, schlafe $([math]::ceiling(($script:TimeBase / 2))) Sekunden." -ForegroundColor DarkGreen
                Write-ColorOut "$counter/$script:CounterMax Passes without any activity. // $counter/$script:CounterMax Durchgaenge ohne Aktivitaet." -ForegroundColor Green
                $counter ++
                Start-Sleep -Seconds $([math]::ceiling(($script:TimeBase / 2)))
            }
        }elseif($script:Mode -eq "cpu"){
            $CPUstats = Get-ComputerStats
            if($CPUstats -gt $script:CPUthresh){
                Write-ColorOut "$(Get-Date -Format 'dd.MM.yy, HH:mm:ss')" -NoNewline
                Write-ColorOut " - CPU usage is $($CPUstats)% = above $($script:CPUthresh)%, sleeping for $script:TimeBase seconds. // CPU-Auslastung $($CPUstats)% = ueber $($script:CPUthresh)%, schlafe $script:TimeBase Sekunden." -ForegroundColor DarkGray
                $counter = 0
                Start-Sleep -Seconds $script:TimeBase
            }else{
                Write-ColorOut "$(Get-Date -Format 'dd.MM.yy, HH:mm:ss')" -NoNewline
                Write-ColorOut " - CPU usage $($CPUstats)% = below $($script:CPUthresh)%, sleeping for $([math]::ceiling(($script:TimeBase / 2))) seconds. // CPU-Auslastung $($CPUstats)% = unter $($script:CPUthresh)%, schlafe $([math]::ceiling(($script:TimeBase / 2))) Sekunden." -ForegroundColor DarkGreen
                Write-ColorOut "$counter/$script:CounterMax Passes without any activity. // $counter/$script:CounterMax Durchgaenge ohne Aktivitaet." -ForegroundColor Green
                $counter++
                Start-Sleep -Seconds $([math]::ceiling(($script:TimeBase / 2)))
            }
        }
    }
}

# DEFINITION: Shutdown
Function Start-Shutdown(){
    Write-ColorOut "Shutting down... // Herunterfahren..." -ForegroundColor DarkRed
    Start-Sleep -Seconds 10
    Stop-Computer
}

# DEFINITION: Start it:
Function Start-Everything(){
    Write-ColorOut "flolilo's Preventsleep-Script v2.0 // flolilos Schlaf-Verhinder-Skript v2.0" -ForegroundColor DarkCyan -BackgroundColor Gray
    Write-ColorOut "This script prevents the computer from hibernating. // Dieses Skript hindert den Computer am Standby-Wechsel." -ForegroundColor DarkCyan -BackgroundColor Gray -Indentation 4
    Write-ColorOut "Do not close this window if a script opened it! // Dieses Fenster nicht schliessen falls es von einem Prozess geoeffnet wurde!" -ForegroundColor Red -BackgroundColor White
    Write-ColorOut "Process-ID of this script is: // Prozess-ID dieses Skripts ist:`t" -NoNewLine -ForegroundColor Cyan
    Write-ColorOut "$PID`r`n" -ForegroundColor Magenta

    Get-UserVars
    Start-Preventing

    Write-ColorOut "`r`n$(Get-Date -Format 'dd.MM.yy, HH:mm:ss')" -NoNewline
    Write-ColorOut " - Done! // Fertig!" -ForegroundColor Green

    if($script:Shutdown -eq 1){
        Start-Shutdown
    }
}

Start-Everything
