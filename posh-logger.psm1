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
        [Parameter(Mandatory=$False)][Int32]$LogsToKeep = 5
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
        $LogPath = $invocation.PSCommandPath -replace '(.*\.)(ps1)','$1log'
        Write-Verbose "Created log file $LogPath"
    }

    # Create our custom object props
    $logger = New-Object -TypeName PSObject
    Add-Member -InputObject $logger -MemberType NoteProperty -Name LogPath -Value $LogPath
    Add-Member -InputObject $logger -MemberType NoteProperty -Name RotateSize -Value $RotateSize
    Add-Member -InputObject $logger -MemberType NoteProperty -Name OutputToConsole -Value $OutputToConsole
    Add-Member -InputObject $logger -MemberType NoteProperty -Name LogsToKeep -Value $LogsToKeep

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
		        $newname = $this.LogPath -replace '(.*\.)(log)','$1'
                $newname += "$(get-date -UFormat %Y%m%d-%M%S).log"
		        Move-Item -Path $this.LogPath -Destination $newname -Force

                # clean up old files
                Get-ChildItem -Path (Split-Path $this.LogPath -Parent) | ? {$_.Name -match '^.*\.\d+-\d+\.log' } | Sort-Object -Descending -Property LastWriteTime | Select -Skip $this.LogsToKeep | Remove-Item -Force -Confirm:$false
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
            "WARN" {$doOutput=$true; continue}
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

            if($VerbosePreference -eq 'continue')
            {
                Write-Verbose $thisMessage
            }
            if($DebugPreference -eq 'continue')
            {
                Write-Debug $thisMessage
            }
        }
    }

    $info = 
    {
        Param(
            [Parameter(Mandatory=$True)][ValidateNotNullOrEmpty()][string]$Message
        )
        $this.writeLog($Message, [LogType]::INFO)
    }

    $warn = 
    {
        Param(
            [Parameter(Mandatory=$True)][ValidateNotNullOrEmpty()][string]$Message
        )
        $this.writeLog($Message, [LogType]::WARN)
    }

    $error = 
    {
        Param(
            [Parameter(Mandatory=$True)][ValidateNotNullOrEmpty()][string]$Message
        )
        $this.writeLog($Message, [LogType]::ERROR)
    }

    $debug = 
    {
        Param(
            [Parameter(Mandatory=$True)][ValidateNotNullOrEmpty()][string]$Message
        )
        $this.writeLog($Message, [LogType]::DEBUG)
    }

    Add-Member -InputObject $logger -MemberType ScriptMethod -Name WriteLog -Value $writeLog @args
    Add-Member -InputObject $logger -MemberType ScriptMethod -Name Info -Value $info @args
    Add-Member -InputObject $logger -MemberType ScriptMethod -Name Warn -Value $warn @args
    Add-Member -InputObject $logger -MemberType ScriptMethod -Name Error -Value $error @args
    Add-Member -InputObject $logger -MemberType ScriptMethod -Name Debug -Value $debug @args

    # Put the object on the pipeline
    $logger
}

Export-ModuleMember *