function New-ParkingClient {
	<#
	.SYNOPSIS 
	This cmdlet was written to simplify/automate the process of adding a new parking client to the Clancy7 system. 

	.DESCRIPTION
	This cmdlet was written to simplify/automate the process of adding a new parking client to the Clancy7 system. 

	.PARAMETER ClientName
	The name of the new parking client to be added to Clancy7. This will be the name used for the folder on M: or Y:, which ever has more available disk space.	
			i.e. M:\CCCClients\namemast.dbf

	.PARAMETER ClientShortName
	The short name of the new parking client. 4 Characters, max. 

	.PARAMETER ClientState
	The two letter abbreviation for the new parking client's home state. 2 Characters, max.

	.EXAMPLE
	New-ParkingClient

	.EXAMPLE
	New-ParkingClient -ClientName "ParkPros" -ClientShortName "PRKP" -ClientHomeState "NV"

	.NOTES
	Author: Clancy Systems (Aaron)
	Last Updated: October 2025

	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory=$true)]
		[string]$Name = $(Read-Host "`nEnter the full name of the new parking client.`nThis is the name that will be used for the data folder name"),

		[Parameter(Mandatory=$true)]
		[string]$ShortName = $(Read-Host "`nEnter the short name of the new parking client.`nThis is the name that will be used as the client's short name.`n4 Characters long"),

		[Parameter(Mandatory=$true)]
		[string]$State = $(Read-Host "`nEnter the 2 letter abbreviation for this client's home state`n")
	)

	Write-Host "`n=== NEW CLANCY7 PARKING CLIENT ===" -ForegroundColor Green
	Write-Host "You are running PowerShell $($PSVersionTable.PSVersion)" -ForegroundColor Gray

	$setupResults = [System.Collections.Generic.List[object]]::new()

	function Add-ClientSetupResult {
		param(
			[Parameter(Mandatory=$true)]
			[string]$Step,

			[Parameter(Mandatory=$true)]
			[string]$Status,

			[Parameter(Mandatory=$true)]
			[string]$Details
		)

		$setupResults.Add([pscustomobject]@{
			Step = $Step
			Status = $Status
			Details = $Details
		}) | Out-Null
	}

	function Show-ClientSetupSummary {
		Write-Host "`n=== NEW PARKING CLIENT SETUP SUMMARY ===" -ForegroundColor Cyan

		if ($setupResults.Count -eq 0) {
			Write-Host "No setup actions were recorded." -ForegroundColor Gray
			return
		}

		foreach ($result in $setupResults) {
			$color = switch ($result.Status) {
				"Success" { "Green" }
				"Skipped" { "Yellow" }
				"Failed" { "Red" }
				default { "Gray" }
			}

			Write-Host ("[{0}] {1}: {2}" -f $result.Status, $result.Step, $result.Details) -ForegroundColor $color
		}
	}

	function Get-ClancyWindowsCredential {
		do {
			Write-Host "`nEnter the Windows credentials for the Clancy servers." -ForegroundColor Blue
			$credential = Get-Credential -UserName Mobile.Clancy\Administrator

			if ($null -eq $credential) {
				Write-Host "No credentials were entered. Please try again, or press CTRL+C to stop this cmdlet." -ForegroundColor Red
			}
		} until ($null -ne $credential)

		return $credential
	}

	function Test-IsCredentialFailure {
		param(
			[Parameter(Mandatory=$true)]
			[System.Management.Automation.ErrorRecord]$ErrorRecord
		)

		$errorText = @(
			$ErrorRecord.Exception.Message
			$ErrorRecord.FullyQualifiedErrorId
			($ErrorRecord | Out-String)
		) -join " "

		return ($errorText -match "(?i)(access is denied|authentication|credential|credentials|unauthorized|logon failure|user name or password|password is incorrect|cannot be authenticated|401)")
	}

	function Invoke-WithCredentialRetry {
		param(
			[Parameter(Mandatory=$true)]
			[string]$Activity,

			[Parameter(Mandatory=$true)]
			[scriptblock]$ScriptBlock,

			[Parameter(Mandatory=$true)]
			[ref]$Credential
		)

		while ($true) {
			try {
				return & $ScriptBlock $Credential.Value
			} catch {
				if (Test-IsCredentialFailure -ErrorRecord $_) {
					Write-Host "`n$Activity failed because the Windows credentials were rejected. Please try again, or press CTRL+C to stop this cmdlet." -ForegroundColor Red
					$Credential.Value = Get-ClancyWindowsCredential
					continue
				}

				throw
			}
		}
	}

	function Copy-ClientSetupFile {
		param(
			[Parameter(Mandatory=$true)]
			[string]$Source,

			[Parameter(Mandatory=$true)]
			[string]$Destination,

			[Parameter(Mandatory=$true)]
			[string]$Step
		)

		try {
			if (-not (Test-Path -Path $Source -PathType Leaf)) {
				throw "Source file not found: $Source"
			}

			if (-not (Test-Path -Path $Destination -PathType Container)) {
				throw "Destination folder not found: $Destination"
			}

			Copy-Item -Path $Source -Destination $Destination -Force -Verbose -ErrorAction Stop
			Add-ClientSetupResult -Step $Step -Status "Success" -Details "Copied $Source to $Destination."
			Write-Host "$Step completed successfully." -ForegroundColor Green
			return $true
		} catch {
			Add-ClientSetupResult -Step $Step -Status "Failed" -Details $_.Exception.Message
			Write-Host "$Step failed: $($_.Exception.Message)" -ForegroundColor Red
			return $false
		}
	}

	try {

	#Check for necessary modules
	Write-Host "`nChecking Modules ..." -ForegroundColor Yellow
	if (-not (Get-Module -ListAvailable -Name 'IISAdministration')) {
		Write-Host "The IISAdministration Module is required for this cmdlet to run." -ForegroundColor Red
		Write-Host "Get it using 'Install-Module IISAdministration' and re-run this cmdlet." -ForegroundColor Gray
		Add-ClientSetupResult -Step "Module check" -Status "Failed" -Details "IISAdministration module is missing."
		return $null
	} 
	if (-not (Get-Module -ListAvailable -Name 'CredentialManager')) {
		Write-Host "The CredentialManager Module is required for this cmdlet to run." -ForegroundColor Red
		Write-Host "Get it using 'Install-Module CredentialManager' and re-run this cmdlet." -ForegroundColor Gray
		Add-ClientSetupResult -Step "Module check" -Status "Failed" -Details "CredentialManager module is missing."
		return $null
	}
	Write-Host "Modules present!" -ForegroundColor Green	
	Add-ClientSetupResult -Step "Module check" -Status "Success" -Details "Required modules are installed."

	#Get the IP addresses of the computers we'll need to remote into in case the name just doesn't want to work
	Write-Host "`nObtaining IP Addresses of remote servers ..."
	$dataserver_name = "DATASERVER"
	$mus1_name = "MUS1"
	$mus2_name = "MUS2"
	$ds_ip = (ping -4 -n 1 $dataserver_name | Select-String -Pattern '\d{1,3}(\.\d{1,3}){3}' -AllMatches).Matches.Value[0]
	$mus1_ip = (ping -4 -n 1 $mus1_name | Select-String -Pattern '\d{1,3}(\.\d{1,3}){3}' -AllMatches).Matches.Value[0]
	$mus2_ip = (ping -4 -n 1 $mus2_name | Select-String -Pattern '\d{1,3}(\.\d{1,3}){3}' -AllMatches).Matches.Value[0]
	Write-Host "$dataserver_name`: $ds_ip"
	Write-Host "$mus1_name`: $mus1_ip"
	Write-Host "$mus2_name`: $mus2_ip"

	#What will the new client's information be
	$Credentials = Get-ClancyWindowsCredential
	Add-ClientSetupResult -Step "Windows credentials" -Status "Success" -Details "Credentials were collected for remote server actions."
	$Name = $Name.ToUpper()
	$ShortName = $ShortName.ToUpper()
	$State = $State.ToUpper()


	#Validate and format the home state input as the first thing
	$StateLen = $State.Length
	if ($StateLen -ne 2) {
		Write-Host "`nThe state abbreviation should be 2 characters long." -ForegroundColor Red
		$State = Read-Host "Please enter the 2 letter abbreviation for this client's home state"
		$State = $State.ToUpper()
		$StateLen = $State.Length
		if ($StateLen -ne 2) {
			#enuf lol
			Add-ClientSetupResult -Step "Input validation" -Status "Failed" -Details "State abbreviation was not 2 characters long."
			return $null
		}
	}
	Write-Host "State is 2 characters long." -ForegroundColor Green
	Add-ClientSetupResult -Step "Input validation" -Status "Success" -Details "Client name, short name, and state were normalized."

#####Anyone running this New-ParkingClient cmdlet should have the correct ClancySystems drive mappings on their workstation. Run "Validate-Mappings" cmdlet in this module. 
	$m_path = "M:\" + $Name
	$y_path = "Y:\" + $Name
	$e_path = "E:\" + $Name
	$f_path = "F:\" + $Name
	$p_path = "P:\unloads\" + $Name
	$o_path = "O:\unloads\" + $Name
	$local_unloads = "C:\unloads\" + $Name
	$local_vpath = "C:\unloads\" + $Name + "\comm\"
	$p_vpath = "P:\unloads\" + $Name + "\comm\"
	$o_vpath = "O:\unloads\" + $Name + "\comm\"
	$the_drive = "" #the drive letter used to create the new client folder (m or y)
	$local_drive = "" #the drive letter used local to dataserver (e or f)
	$the_path = "" #the path that was taken, the full path here
	$dataserver_path = "" #the local path for the dataserver?
	$find = "EmptyData"

	Write-Host "`nChecking to make sure the client folder doesn't already exist..." -ForegroundColor Yellow
	if ((Test-Path $m_path) -or (Test-Path $y_path)) {
		#if the folder name already exists on M or Y then terminate this script and force the user "to go deal with that" outside of this utility.
		Write-Host "`nThe folder for parking client $Name already exists on one of the dataserver drives M or Y.`n" -ForegroundColor Red
		Write-Host "`nYou'll have to address that problem outside of the scope of this cmdlet and then re-run it!`n" -ForegroundColor Red
		Add-ClientSetupResult -Step "Dataserver folder pre-check" -Status "Failed" -Details "A client folder already exists on M: or Y:. No further changes were made."
		throw "A client folder already exists on M: or Y: for $Name."
	} else {
		#neither folder exists, as they should not
		Write-Host "The client folder does not already exist." -ForegroundColor Green
		Write-Host "`nChecking to see if M: or Y: has more space ..." -ForegroundColor Yellow

		#compare the disk space between M and Y and use the drive with more free space to create the new client.
		$m_space = [math]::Round((Get-PSDrive M).free / 1gb, 2)
		$y_space = [math]::Round((Get-PSDrive Y).free / 1gb, 2)
		if ($m_space -gt $y_space) {
			Write-Host "`nCreating Client folder on M:\`n" -ForegroundColor Gray
			New-Item -Path $m_path -ItemType Directory -ErrorAction Stop | Out-Null
			$the_drive = "M"
			$local_drive = "E"
			$dataserver_path = "E:\" + $Name
			$the_path = "M:\" + $Name
			Add-ClientSetupResult -Step "Dataserver folder" -Status "Success" -Details "Created $the_path."
		} else { 
			Write-Host "`nCreating Client folder on Y:\`n" -ForegroundColor Gray
			New-Item -Path $y_path -ItemType Directory -ErrorAction Stop | Out-Null
			$the_drive = "Y"
			$local_drive = "F"
			$dataserver_path = "F:\" + $Name
			$the_path = "Y:\" + $Name
			Add-ClientSetupResult -Step "Dataserver folder" -Status "Success" -Details "Created $the_path."
		}
	}

####Copy the empty client folder on M: or Y: into the newly created client folder.
	#I do it like this with Test-Path to also test to make sure that the folder exists
	Write-Host "`nAttempting to copy EmptyData\* into the new folder ...`n" -ForegroundColor Yellow
	$empty_path = $the_drive + ":\EmptyData\"
	if (Test-Path $m_path) {
		Copy-Item -Recurse $empty_path* $m_path -ErrorAction Stop
		Add-ClientSetupResult -Step "Dataserver seed files" -Status "Success" -Details "Copied $empty_path* to $m_path."
	} elseif (Test-Path $y_path) {
		Copy-Item -Recurse $empty_path* $y_path -ErrorAction Stop
		Add-ClientSetupResult -Step "Dataserver seed files" -Status "Success" -Details "Copied $empty_path* to $y_path."
	} else {
		#The folder we attempted to create doesn't exist after trying to create it above, fail
		Write-Host "`nThe new client folder was not created and not found. Exiting.`n" -ForegroundColor Red
		Add-ClientSetupResult -Step "Dataserver seed files" -Status "Failed" -Details "The new client folder was not found after creation."
		throw "The new client folder was not found after creation."
	}

####Remote into DATASERVER and create the SMBShare (Windows Shared Folder) for the new parking client folder, share with everyone
	#This creates the SMB share at the server level, the share is created normally, can be accessed over the network but it doesn't use
	#The same legacy channels that the next line does to make it display correctly in Windows Explorer 

	Write-Host "`nAttempting to remote into DATASERVER ($ds_ip) and share the client folder ..." -ForegroundColor Yellow
	
	Invoke-WithCredentialRetry -Activity "Creating the DATASERVER SMB share" -Credential ([ref]$Credentials) -ScriptBlock {
		param($CurrentCredential)

		Invoke-Command -ComputerName $dataserver_name -Credential $CurrentCredential -ErrorAction Stop -ScriptBlock {
			param($folderName, $folderPath)
		
			#Create the share using New-SMBShare ...
			New-SMBShare -Name $folderName -Path $folderPath -FullAccess Everyone -ErrorAction Stop
		
			#Create the share with Net Share so it displays correctly in Windows Explorer.
			$netShareCommand = 'net share "{0}={1}" /GRANT:Everyone,FULL' -f $folderName, $folderPath
			cmd /c $netShareCommand
			if ($LASTEXITCODE -ne 0) {
				throw "net share failed with exit code $LASTEXITCODE."
			}

		} -ArgumentList $Name, $dataserver_path
	} | Out-Null
	Add-ClientSetupResult -Step "DATASERVER share" -Status "Success" -Details "Created SMB share $Name for $dataserver_path."

#####Now create the folders on MUS1 and MUS2 unloads, copy EmptyData into them, create the IIS-Site and Virtual Directory on both as well. 
	Write-Host "`nAttempting to create unloads directories on P:\unloads and O:\unloads ...`n" -ForegroundColor Yellow
	$pUnloadReady = $false
	$oUnloadReady = $false
	$pCommReady = $false
	$oCommReady = $false

	try {
		if (Test-Path -Path $p_path -PathType Container) {
			Write-Host "$p_path already exists; continuing with the existing folder.`n" -ForegroundColor Yellow
			Add-ClientSetupResult -Step "P:\ unloads folder" -Status "Skipped" -Details "$p_path already existed."
		} else {
			New-Item -Path $p_path -ItemType Directory -ErrorAction Stop | Out-Null
			Write-Host "$p_path was successfully created.`n" -ForegroundColor Green
			Add-ClientSetupResult -Step "P:\ unloads folder" -Status "Success" -Details "Created $p_path."
		}
		$pUnloadReady = $true
	} catch {
		Write-Host "Error creating unloads folder on P:\unloads\ - $($_.Exception.Message)" -ForegroundColor Red
		Add-ClientSetupResult -Step "P:\ unloads folder" -Status "Failed" -Details $_.Exception.Message
	}
		
	try {
		if (Test-Path -Path $o_path -PathType Container) {
			Write-Host "$o_path already exists; continuing with the existing folder.`n" -ForegroundColor Yellow
			Add-ClientSetupResult -Step "O:\ unloads folder" -Status "Skipped" -Details "$o_path already existed."
		} else {
			New-Item -Path $o_path -ItemType Directory -ErrorAction Stop | Out-Null
			Write-Host "$o_path was successfully created.`n" -ForegroundColor Green
			Add-ClientSetupResult -Step "O:\ unloads folder" -Status "Success" -Details "Created $o_path."
		}
		$oUnloadReady = $true
	} catch {
		Write-Host "Error creating unloads folder on O:\unloads\ - $($_.Exception.Message)" -ForegroundColor Red
		Add-ClientSetupResult -Step "O:\ unloads folder" -Status "Failed" -Details $_.Exception.Message
	}
	
#####Copy the EmptyData folder into the newly created folders...
	Write-Host "`nAttempting to copy EmptyData\* into the unloads ..." -ForegroundColor Yellow
	if ($pUnloadReady) {
		try {
			Copy-Item -Recurse P:\unloads\EmptyData\* $p_path -ErrorAction Stop
			Add-ClientSetupResult -Step "P:\ unloads seed files" -Status "Success" -Details "Copied P:\unloads\EmptyData\* to $p_path."
			Write-Host "Copied P:\unloads\EmptyData\* to $p_path." -ForegroundColor Green
		} catch {
			Add-ClientSetupResult -Step "P:\ unloads seed files" -Status "Failed" -Details $_.Exception.Message
			Write-Host "Error copying EmptyData to $p_path - $($_.Exception.Message)" -ForegroundColor Red
		}
	} else {
		Add-ClientSetupResult -Step "P:\ unloads seed files" -Status "Skipped" -Details "$p_path was not available."
	}

	if ($oUnloadReady) {
		try {
			Copy-Item -Recurse O:\unloads\EmptyData\* $o_path -ErrorAction Stop
			Add-ClientSetupResult -Step "O:\ unloads seed files" -Status "Success" -Details "Copied O:\unloads\EmptyData\* to $o_path."
			Write-Host "Copied O:\unloads\EmptyData\* to $o_path." -ForegroundColor Green
		} catch {
			Add-ClientSetupResult -Step "O:\ unloads seed files" -Status "Failed" -Details $_.Exception.Message
			Write-Host "Error copying EmptyData to $o_path - $($_.Exception.Message)" -ForegroundColor Red
		}
	} else {
		Add-ClientSetupResult -Step "O:\ unloads seed files" -Status "Skipped" -Details "$o_path was not available."
	}

#####Make sure the comm's directory is present before you try to create the IIS-Sites 
	if (-not (Test-Path -Path $p_vpath -PathType Container)) {
		Write-Host "The directory 'P:\unloads\$Name\comm\' wasn't created. Continuing and recording the IIS/file work as needed." -ForegroundColor Red
		Add-ClientSetupResult -Step "P:\ comm folder" -Status "Failed" -Details "$p_vpath was not found."
	} else {
		$pCommReady = $true
		Add-ClientSetupResult -Step "P:\ comm folder" -Status "Success" -Details "$p_vpath exists."
	}
	if (-not (Test-Path -Path $o_vpath -PathType Container)) {
		Write-Host "The directory 'O:\unloads\$Name\comm\' wasn't created. Continuing and recording the IIS/file work as needed." -ForegroundColor Red
		Add-ClientSetupResult -Step "O:\ comm folder" -Status "Failed" -Details "$o_vpath was not found."
	} else {
		$oCommReady = $true
		Add-ClientSetupResult -Step "O:\ comm folder" -Status "Success" -Details "$o_vpath exists."
	}

	try {
#####Create the IIS-Sites and Virtual Directories on both unload servers
		Write-Host "`nAttempting to create the IIS site and virtual directory on MUS1 ($mus1_ip) ..." -ForegroundColor Yellow
		Invoke-WithCredentialRetry -Activity "Creating the IIS site on MUS1" -Credential ([ref]$Credentials) -ScriptBlock {
			param($CurrentCredential)

			Invoke-Command -ComputerName $mus1_name -Credential $CurrentCredential -ErrorAction Stop -ScriptBlock {
				param($Name, $local_unloads, $local_vpath)
				New-WebApplication -Name $Name -Site "Default Web Site" -PhysicalPath $local_unloads -ApplicationPool "DefaultAppPool" -ErrorAction Stop | Out-Null
				New-WebVirtualDirectory -Site "Default Web Site" -Application $Name -Name "DemoTickets" -PhysicalPath $local_vpath -ErrorAction Stop | Out-Null

			} -ArgumentList $Name, $local_unloads, $local_vpath
		} | Out-Null
		Write-Host "The IIS Site and Virtual Directory (DemoTickets) were created on MUS1 successfully." -ForegroundColor Green
		Add-ClientSetupResult -Step "MUS1 IIS" -Status "Success" -Details "Created IIS application and DemoTickets virtual directory for $Name."
	} catch {
		Write-Host "`nFailed to create the IIS site for $Name on MUS1: $($_.Exception.Message)" -ForegroundColor Red
		Add-ClientSetupResult -Step "MUS1 IIS" -Status "Failed" -Details $_.Exception.Message
	}

	try {
		Write-Host "`nAttempting to create the IIS site and virtual directory on MUS2 ($mus2_ip) ..." -ForegroundColor Yellow
		Invoke-WithCredentialRetry -Activity "Creating the IIS site on MUS2" -Credential ([ref]$Credentials) -ScriptBlock {
			param($CurrentCredential)

			Invoke-Command -ComputerName $mus2_name -Credential $CurrentCredential -ErrorAction Stop -ScriptBlock {
				param($Name, $local_unloads, $local_vpath)
				New-WebApplication -Name $Name -Site "Default Web Site" -PhysicalPath $local_unloads -ApplicationPool "DefaultAppPool" -ErrorAction Stop | Out-Null
				New-WebVirtualDirectory -Site "Default Web Site" -Application $Name -Name "DemoTickets" -PhysicalPath $local_vpath -ErrorAction Stop | Out-Null

			} -ArgumentList $Name, $local_unloads, $local_vpath
		} | Out-Null
		Write-Host "The IIS Site and Virtual Directory (DemoTickets) were created on MUS2 successfully." -ForegroundColor Green
		Add-ClientSetupResult -Step "MUS2 IIS" -Status "Success" -Details "Created IIS application and DemoTickets virtual directory for $Name."
	} catch {
		Write-Host "`nFailed to create the IIS site for $Name on MUS2: $($_.Exception.Message)" -ForegroundColor Red
		Add-ClientSetupResult -Step "MUS2 IIS" -Status "Failed" -Details $_.Exception.Message
	}


#####Modify custom.a, UNLOAD.ASP, LOOKUP.ASP, SENDDATA.BAT
	$customA = $p_vpath + "Custom.a"
	$menuT = $p_vpath + "menu.t"
	$sendDataFile = $p_vpath + "SENDDATA.BAT"
	$unloadFile = $p_path + "\Unload.asp"
	$lookupFile = $p_path + "\LOOKUP.ASP"

#Custom.a
	try {
		if (Test-Path $customA -PathType leaf) {
			Write-Host "`nCustom.a is present. Attempting to edit with $Name info..." -ForegroundColor Yellow
			
			#The things to replace in the file
			$LineOne = "US" + $Name
			$LineTwo = "HS" + $State
			$LineThree = "MS" + $Name
			$UI = "UI107.1.38.45:80/EMPTYDATA"
			$AI = "AI173.164.42.133:80/EMPTYDATA"
			$LineTwelve = "UI107.1.38.45:80/" + $Name
			$LineThirteen = "AI173.164.42.133:80/" + $Name
			

			#actually replacing those lines below
			$replacements = @{
				"USEMPTYDATA" = $LineOne
				"USCO" = $LineTwo
				"MSEMPTY PARKING" = $LineThree
				$UI = $LineTwelve
				$AI = $LineThirteen
			}

			$content = Get-Content $customA -ErrorAction Stop
			
			foreach ($pair in $replacements.GetEnumerator()) {
				$content = $content -replace $pair.Key, $pair.Value
			}

			Set-Content -Path $customA -Value $content -ErrorAction Stop

			if (Select-String -Path $customA -Pattern $LineOne -ErrorAction Stop) {
				Write-Host "Custom.a was successfully edited with $Name information." -ForegroundColor Green
				Add-ClientSetupResult -Step "Custom.a update" -Status "Success" -Details "Updated $customA with $Name information."
			} else {
				Write-Host "Custom.a might not have been edited correctly." -ForegroundColor Red
				Add-ClientSetupResult -Step "Custom.a update" -Status "Failed" -Details "$customA did not contain the expected $Name value after editing."
			}	

		} else { 
			Write-Host "`nCustom.a was not found in the comm directory. Continuing and recording this in the summary." -ForegroundColor Red
			throw "File not found: $customA"
		}
	} catch {
		Write-Host "Custom.a update failed: $($_.Exception.Message)" -ForegroundColor Red
		Add-ClientSetupResult -Step "Custom.a update" -Status "Failed" -Details $_.Exception.Message
	}
#SENDDATA.BAT
	try {
		if (Test-Path $sendDataFile -PathType leaf) {
			Write-Host "`nSENDDATA.BAT present. Attempting to edit with $Name info ..." -ForegroundColor Yellow

			$lines = Get-Content $sendDataFile -ErrorAction Stop

			$lines = $lines | ForEach-Object {
				$_.Replace($find, $Name)	
			}

			Set-Content -Path $sendDataFile -Value $lines -ErrorAction Stop

			if (Select-String -Path $sendDataFile -Pattern $find -ErrorAction Stop) {
				Write-Host "SENDDATA.BAT might not have been edited correctly." -ForegroundColor Red
				Add-ClientSetupResult -Step "SENDDATA.BAT update" -Status "Failed" -Details "$sendDataFile still contains $find after editing."
			} else {
				Write-Host "SENDDATA.BAT was successfully edited with $Name information." -ForegroundColor Green
				Add-ClientSetupResult -Step "SENDDATA.BAT update" -Status "Success" -Details "Updated $sendDataFile with $Name information."
			}	
			
		} else {
			Write-Host "`nSENDDATA.BAT was not found in the comm directory. Continuing and recording this in the summary." -ForegroundColor Red
			throw "File not found: $sendDataFile"
		}
	} catch {
		Write-Host "SENDDATA.BAT update failed: $($_.Exception.Message)" -ForegroundColor Red
		Add-ClientSetupResult -Step "SENDDATA.BAT update" -Status "Failed" -Details $_.Exception.Message
	}
#Unload.asp
	try {
		if (Test-Path $unloadFile -PathType leaf) {
			Write-Host "`nUnload.asp present. Attempting to edit with $Name info ... " -ForegroundColor Yellow
			
			$lines = Get-Content $unloadFile -ErrorAction Stop

			$lines = $lines | ForEach-Object {
				$_.Replace($find, $Name)	
			}

			Set-Content -Path $unloadFile -Value $lines -ErrorAction Stop

			if (Select-String -Path $unloadFile -Pattern $find -ErrorAction Stop) {
				Write-Host "Unload.asp might not have been edited correctly." -ForegroundColor Red
				Add-ClientSetupResult -Step "Unload.asp update" -Status "Failed" -Details "$unloadFile still contains $find after editing."
			} else {
				Write-Host "Unload.asp was successfully edited with $Name information." -ForegroundColor Green
				Add-ClientSetupResult -Step "Unload.asp update" -Status "Success" -Details "Updated $unloadFile with $Name information."
			}	
		} else {
			Write-Host "`nUnload.asp was not found in the unloads directory. Continuing and recording this in the summary." -ForegroundColor Red
			throw "File not found: $unloadFile"
		}
	} catch {
		Write-Host "Unload.asp update failed: $($_.Exception.Message)" -ForegroundColor Red
		Add-ClientSetupResult -Step "Unload.asp update" -Status "Failed" -Details $_.Exception.Message
	}
#LOOKUP.ASP
	try {
		if (Test-Path $lookupFile -PathType leaf) {
			Write-Host "`nLOOKUP.ASP present. Attempting to modify with $Name info ..." -ForegroundColor Yellow
			
			$lines = Get-Content $lookupFile -ErrorAction Stop

			$lines = $lines | ForEach-Object {
				$_.Replace($find, $Name)	
			}

			Set-Content -Path $lookupFile -Value $lines -ErrorAction Stop

			if (Select-String -Path $lookupFile -Pattern $find -ErrorAction Stop) {
				Write-Host "LOOKUP.ASP might not have been edited correctly." -ForegroundColor Red
				Add-ClientSetupResult -Step "LOOKUP.ASP update" -Status "Failed" -Details "$lookupFile still contains $find after editing."
			} else {
				Write-Host "LOOKUP.ASP was successfully edited with $Name information." -ForegroundColor Green
				Add-ClientSetupResult -Step "LOOKUP.ASP update" -Status "Success" -Details "Updated $lookupFile with $Name information."
			}	
		} else {
			Write-Host "`nLOOKUP.ASP was not found in the unloads directory. Continuing and recording this in the summary." -ForegroundColor Red
			throw "File not found: $lookupFile"
		}
	} catch {
		Write-Host "LOOKUP.ASP update failed: $($_.Exception.Message)" -ForegroundColor Red
		Add-ClientSetupResult -Step "LOOKUP.ASP update" -Status "Failed" -Details $_.Exception.Message
	}

#####Copy the modified custom.a, UNLOAD.ASP, LOOKUP.ASP, SENDDATA.BAT to the other unload server and custom.a, Menu.t the dataserver folder.
	Write-Host "`nAttempting to copy the modified files to the other unload server and dataserver..." -ForegroundColor Yellow
	
	#copy the custom.a file to O:\client\comm\ and P:\client\comm\
	Copy-ClientSetupFile -Source $customA -Destination $o_vpath -Step "Copy Custom.a to O:\ comm" | Out-Null

	#copy the sendDataFile to O:\client\comm\ and P:\client\comm\
	Copy-ClientSetupFile -Source $sendDataFile -Destination $o_vpath -Step "Copy SENDDATA.BAT to O:\ comm" | Out-Null

	#copy the unloadfile to O:\ and P:\
	Copy-ClientSetupFile -Source $unloadFile -Destination $o_path -Step "Copy Unload.asp to O:\ unloads" | Out-Null

	#copy the lookupfile to O:\ and P:\ 
	Copy-ClientSetupFile -Source $lookupFile -Destination $o_path -Step "Copy LOOKUP.ASP to O:\ unloads" | Out-Null

	#copy custom.a and menu.t to the data folder on M or Y
	Copy-ClientSetupFile -Source $customA -Destination $the_path -Step "Copy Custom.a to dataserver folder" | Out-Null
	Copy-ClientSetupFile -Source $menuT -Destination $the_path -Step "Copy menu.t to dataserver folder" | Out-Null

	$tp = $o_path + "\LOOKUP.ASP"
	if (Test-Path -Path $tp -PathType leaf) {
		if (Select-String -Path $tp -Pattern $find -ErrorAction Stop) {
			Write-Host "`nNew Parking Client $Name may not have totally been setup correctly. Check the configuration!" -ForegroundColor Red	
			Add-ClientSetupResult -Step "O:\ LOOKUP.ASP verification" -Status "Failed" -Details "$tp still contains $find."
		} else {
			Write-Host "`nNew Clancy7 Parking Client $Name appears to be setup correctly!"	-ForegroundColor Green
			Add-ClientSetupResult -Step "O:\ LOOKUP.ASP verification" -Status "Success" -Details "$tp contains $Name information."
		}
	} else {
		Add-ClientSetupResult -Step "O:\ LOOKUP.ASP verification" -Status "Skipped" -Details "$tp was not found."
	}

	Write-Host "`nAttempting to insert a new row into the Clientloc database on P:\ and O:\ ..."
	$ps32Path = "$env:SystemRoot\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"

	$scriptPath = "$env:TEMP\AddClient32.ps1"

	$scriptContent = @"
	Import-Module ClancySystems

	`$values = @{
	    CLIENTNAME = '$Name'
		DRIVEPATH = '\\DATASERVER.MOBILE.CLANCY\$local_drive\$Name\'
		FIRSTDUE = 30
		SECONDDUE = 45
		BLDPMFDUE = `$true
		HSTATE = 'CO'
		BUILDBOOT = `$true
		BOOTCODES = ''
		BOOTTOTAL = 0.00
		NODENAME = '$Name'
		BUILDVBOOT = `$false
		BUILDVMULT = `$false
		BUILDPINFO = `$false
		NAMELINK = `$true
		PACKDATA = `$true
		PHCHGRUN = ([DateTime]::Now).Date
		WEBGROUP = ''
		GDP_BUILD = `$false
		GDPLASTDT = ([DateTime]::Now).Date
		GDPTICKNAM = ''
		GDPDISPNAM = ''
		GDPBLDBTCH = `$false
		GDPCODE = ''
		GDPRUNCMD = ''
		GDPDAYSBAC = 0
		GDPPOSTISS = ''
		SERVICECO = ''
		SHORTNAME = 'ARCL'
		CITYCODE = ''
		WACODE = ''
		TITLE = '$Name'
		BUILDSL = `$false
		SLCODE = ''
		SLDAYS = 0
		REQCODE = ''
		VOIDCODE = ''
		ADDFEEFLAG = `$false
		ADDFEECODE = ''
		LESDAYS = 0
		LESDATE = ([DateTime]::Now).Date
		ININAME = 'ARCL'
		INIDESC = 'ARCL'
		AUTODIOR = ''
		BATCHNUM = ''
		TIMEZONE = 'MST'
		DMVEDIT = `$false
		COURTCODE = ''
		DELMTCHREC = `$false
		WSDEFPDCD = ''
		WSDEFPPCD = ''
		PPALERTS = ''
		PPALTEMAIL = ''
		CHKDIGIT = '7'
		ROID = ''
	}

	Add-VFPTableRow -DbfPath 'P:\unloads\' -TableName 'Clientloc' -Values `$values
	Add-VFPTableRow -DbfPath 'O:\unloads\' -TableName 'Clientloc' -Values `$values
"@
	try {
		Set-Content -Path $scriptPath -Value $scriptContent -Encoding UTF8 -ErrorAction Stop
		Start-Process -FilePath $ps32Path -ArgumentList "-NoExit", "-File `"$scriptPath`"" -ErrorAction Stop
		Add-ClientSetupResult -Step "Clientloc update script" -Status "Success" -Details "Started $scriptPath in 32-bit PowerShell for P:\ and O:\ Clientloc updates."
	} catch {
		Write-Host "Failed to start the Clientloc update script: $($_.Exception.Message)" -ForegroundColor Red
		Add-ClientSetupResult -Step "Clientloc update script" -Status "Failed" -Details $_.Exception.Message
	}
	} catch {
		Write-Host "`nNew-ParkingClient failed: $($_.Exception.Message)" -ForegroundColor Red
		Add-ClientSetupResult -Step "Cmdlet" -Status "Failed" -Details $_.Exception.Message
		throw
	} finally {
		Show-ClientSetupSummary
	}
}


