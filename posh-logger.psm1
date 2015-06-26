# Log type ENUM
Add-Type -TypeDefinition @"
    public enum LogType
    {
        INFO,
        WARN,
        ERROR,
        DEBUG,
        VERBOSE
    }
"@

# Get a logger object that can be passed around
Function Get-Logger
{
    Param(
        [Parameter(Mandatory=$False)][string]$LogPath,
        [Parameter(Mandatory=$False)][Int32]$RotateSize = 10Mb,
        [Parameter(Mandatory=$False)][switch]$OutputToConsole=$False
    )

    # If a LogPath is not included try to get the calling scripts properties and create one, throw an exception if not calling script
    if(!($PSBoundParameters.ContainsKey('LogPath')))
    {
        Set-Variable -Name logFile -Value "" -Scope Global -Option AllScope -Force
        $invocation = (Get-Variable MyInvocation -Scope 1).Value
        if($invocation.PSCommandPath -eq $null)
        {
            Throw "When calling Get-Logger outside of a .ps1 script please include the -LogPath parameter"
        }
        $LogPath = "$($invocation.PSCommandPath).log"
        Write-Verbose "Created log file $LogPath"
    }

    # Create our custom object props
    $logger = New-Object -TypeName PSObject
    Add-Member -InputObject $logger -MemberType NoteProperty -Name LogPath -Value $LogPath
    Add-Member -InputObject $logger -MemberType NoteProperty -Name RotateSize -Value $RotateSize
    Add-Member -InputObject $logger -MemberType NoteProperty -Name OutputToConsole -Value $OutputToConsole


    # Create our custom object methods
    $writeLog = 
    {
        Param(
            [Parameter(Mandatory=$True)][ValidateNotNullOrEmpty()][string]$Message,
            [Parameter(Mandatory=$False)][LogType]$type=[LogType]::INFO
        )

        # Rollover logfile if greater than $rotateSize
        if (Test-Path $this.LogPath)
        {
	        if (((Get-Item $this.LogPath).Length / $this.RotateSize) -gt 1) 
            {
		        # rename current logfile
		        $newname = $this.LogPath + "-" + (Get-Date).Year + "-" + (Get-Date).Month + "-" + (Get-Date).Day + ".archive"
		        Move-Item -Path $this.LogPath -Destination $newname
	        }
        }
	
        # Format the message with date and time
        $currentTime = (Get-Date).toString()
        $thisMessage = $currentTime
        $thisMessage = $thisMessage + " :$($type): "
        $thisMessage = $thisMessage + $Message

        # Should we be logging based on type
        $doOutput = $false
        switch ($type)
        {
            "INFO" {$doOutput=$true; continue}
            "ERROR" {$doOutput=$true; continue}
            "DEBUG" {if($DebugPreference='Continue'){$doOutput=$true}; continue}
            "VERBOSE" {if($VerbosePreference='Continue'){$doOutput=$true}; continue}
        }

        if($doOutput)
        {
            while($true)
            {
                Try
                {
                    $sw = New-Object -TypeName System.IO.StreamWriter($this.LogPath,1)
                    $sw.AutoFlush = $true
                    $sw.WriteLine($thisMessage)
                    $sw.Close()
                    Break
                }
                Catch
                {
                    if(!$_.Exception.Message -contains 'being used by another process')
                    {
                        Throw
                    }
                    Start-Sleep -Milliseconds 500
                    Write-Verbose "File locked, sleeping"
                }
            }
        }
        if($this.OutputToConsole)
        {
            if($type -eq [LogType]::INFO){Write-Host $thisMessage -ForegroundColor White}
            if($type -eq [LogType]::ERROR){Write-Host $thisMessage -ForegroundColor Red}
            if($type -eq [LogType]::WARN){Write-Host $thisMessage -ForegroundColor Yellow}
            if($type -eq [LogType]::DEBUG){Write-Host $thisMessage -ForegroundColor Cyan}
            if($type -eq [LogType]::VERBOSE){Write-Host $thisMessage -ForegroundColor Cyan}
        }
    }

    Add-Member -InputObject $logger -MemberType ScriptMethod -Name WriteLog -Value $writeLog @args

    # Put the object on the pipeline
    $logger
}

Export-ModuleMember *