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

	#Check for necessary modules
	Write-Host "`nChecking Modules ..." -ForegroundColor Yellow
	if (-not (Get-Module -ListAvailable -Name 'IISAdministration')) {
		Write-Host "The IISAdministration Module is required for this cmdlet to run." -ForegroundColor Red
		Write-Host "Get it using 'Install-Module IISAdministration' and re-run this cmdlet." -ForegroundColor Gray
		return $null
	} 
	if (-not (Get-Module -ListAvailable -Name 'CredentialManager')) {
		Write-Host "The CredentialManager Module is required for this cmdlet to run." -ForegroundColor Red
		Write-Host "Get it using 'Install-Module CredentialManager' and re-run this cmdlet." -ForegroundColor Gray
		return $null
	}
	Write-Host "Modules present!" -ForegroundColor Green	

	#Get the IP addresses of the computers we'll need to remote into in case the name just doesn't want to work
	Write-Host "`nObtaining IP Addresses of remote servers ..."
	$ds_ip = (ping -4 -n 1 DATASERVER | Select-String -Pattern '\d{1,3}(\.\d{1,3}){3}' -AllMatches).Matches.Value[0]
	$mus1_ip = (ping -4 -n 1 MUS1 | Select-String -Pattern '\d{1,3}(\.\d{1,3}){3}' -AllMatches).Matches.Value[0]
	$mus2_ip = (ping -4 -n 1 MUS2 | Select-String -Pattern '\d{1,3}(\.\d{1,3}){3}' -AllMatches).Matches.Value[0]
	Write-Host "DATASERVER: $ds_ip"
	Write-Host "MUS1: $mus1_ip"
	Write-Host "MUS2: $mus2_ip"

	#What will the new clinet's information be
	Write-Host "`nEnter THE password so we can reuse it in this cmdlet" -ForegroundColor Blue
	$Credentials = Get-Credential -UserName Mobile.Clancy\Administrator 
	$Name = $Name.ToUpper()
	$ShortName = $ShortName.ToUpper()
	$State = $State.ToUpper()


	#Validate and format the home state input as the first thing
	$StateLen = $State.Length
	if ($StateLen -ne 2) {
		$State = Read-Host "`nThe state abbreviation should be 2 characters long. Please enter the 2 letter abbreviation for this client's home state`n" -ForegroundColor Red
		$StateLen = $State.Length
		if ($StateLen -ne 2) {
			#enuf lol
			return $null
		}
	}
	Write-Host "State is 2 characters long." -ForegroundColor Green

#####Anyone running this New-ParkingClient cmdlet should have the correct ClancySystems drive mappings on their workstation. Run "Repair-Mappings" cmdlet in this module. 
	$m_path = "M:\" + $Name
	$y_path = "Y:\" + $Name
	$e_path = "E:\" + $Name
	$f_path = "F:\" + $Name
	$p_path = "P:\unloads\" + $Name
	$s_path = "O:\unloads\" + $Name
	$local_unloads = "C:\unloads\" + $Name
	$local_vpath = "C:\unloads\" + $Name + "\comm\"
	$p_vpath = "P:\unloads\" + $Name + "\comm\"
	$s_vpath = "O:\unloads\" + $Name + "\comm\"
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
		return $null
	} else {
		#neither folder exists, as they should not
		Write-Host "The client folder does not already exist." -ForegroundColor Green
		Write-Host "`nChecking to see if M: or Y: has more space ..." -ForegroundColor Yellow

		#compare the disk space between M and Y and use the drive with more free space to create the new client.
		$m_space = [math]::Round((Get-PSDrive M).free / 1gb, 2)
		$y_space = [math]::Round((Get-PSDrive Y).free / 1gb, 2)
		if ($m_space -gt $y_space) {
			Write-Host "`nCreating Client folder on M:\`n" -ForegroundColor Gray
			New-Item -Path $m_path -ItemType Directory | Out-Null
			$the_drive = "M"
			$local_drive = "E"
			$dataserver_path = "E:\" + $Name
			$the_path = "M:\" + $Name
		} else { 
			Write-Host "`nCreating Client folder on Y:\`n" -ForegroundColor Gray
			New-Item -Path $y_path -ItemType Directory | Out-Null
			$the_drive = "Y"
			$local_drive = "F"
			$dataserver_path = "F:\" + $Name
			$the_path = "Y:\" + $Name
		}
	}

####Copy the empty client folder on M: or Y: into the newly created client folder.
	#I do it like this with Test-Path to also test to make sure that the folder exists
	Write-Host "`nAttempting to copy EmptyData\* into the new folder ...`n" -ForegroundColor Yellow
	$empty_path = $the_drive + ":\EmptyData\"
	if (Test-Path $m_path) {
		Copy-Item -Recurse $empty_path* $m_path
	} elseif (Test-Path $y_path) {
		Copy-Item -Recurse $empty_path* $y_path		
	} else {
		#The folder we attempted to create doesn't exist after trying to create it above, fail
		Write-Host "`nThe new client folder was not created and not found. Exiting.`n" -ForegroundColor Red
		return $null
	}

####Remote into DATASERVER and create the SMBShare (Windows Shared Folder) for the new parking client folder, share with everyone
	#This creates the SMB share at the server level, the share is created normally, can be accessed over the network but it doesn't use
	#The same legacy channels that the next line does to make it display correctly in Windows Explorer 

	Write-Host "`nAttempting to remote into DATASERVER ($ds_ip) and share the client folder ..." -ForegroundColor Yellow
	
	Invoke-Command -ComputerName "DATASERVER" -Credential $Credentials -ScriptBlock { 
		param($folderName, $folderPath)
		
		#Create the share using New-SMBShare ... 
		New-SMBShare -Name $folderName -Path $folderPath  -FullAccess Everyone 
		
		#Create the share with Net Share ... 
		cmd \c "net share $Name=$dataserver_path /GRANT:$FullAccess,FULL" 

	} -ArgumentList $Name, $dataserver_path

#####Now create the folders on MUS1 and MUS2 unloads, copy EmptyData into them, create the IIS-Site and Virtual Directory on both as well. 
	Write-Host "`nAttempting to create unloads directories on P:\unloads and O:\unloads ...`n" -ForegroundColor Yellow
	try {
		New-Item -Path "$p_path" -ItemType Directory -ErrorAction Stop
		Write-Host "$p_path was successfully created.`n" -ForegroundColor Green
	} catch {
		Write-Output "Error creating unloads folder on P:\unloads\  - $($_.Exception.Message)" -ForegroundColor Red
	}
		
	try {
		New-Item -Path "$s_path" -ItemType Directory -ErrorAction Stop
		Write-Host "$s_path was successfully created.`n" -ForegroundColor Green
	} catch {
		Write-Output "Error creating unloads folder on O:\unloads\ - $($_.Exception.Message)" -ForegroundColor Red
	}
	
#####Copy the EmptyData folder into the newly created folders...
	Write-Host "`nAttempting to copy EmptyData\* into the unloads ..." -ForegroundColor Yellow
	Copy-Item -Recurse P:\unloads\EmptyData\* $p_path
	Copy-Item -Recurse O:\unloads\EmptyData\* $s_path
	Write-Host "Copy complete." -ForegroundColor Green

#####Make sure the comm's directory is present before you try to create the IIS-Sites 
	if (-not (Test-Path -Path $p_vpath -PathType Container)) {
		Write-Host "The directory 'P:\unloads\$Name\comm\' wasn't created! Aborting process ... " -ForegroundColor Red
		return $null
	}
	if (-not (Test-Path -Path $s_vpath -PathType Container)) {
		Write-Host "The directory 'O:\unloads\$Name\comm\' wasn't created! Aborting process ... " -ForegroundColor Red
		return $null
	}

	try {
#####Create the IIS-Sites and Virtual Directories on both unload servers
		Write-Host "`nAttempting to create the IIS site and virtual directory on MUS1 ($mus1_ip) ..." -ForegroundColor Yellow
		Invoke-Command -ComputerName "MUS1"	-Credential $Credentials -ScriptBlock {
			param($Name, $local_unloads, $local_vpath)
			New-WebApplication -Name $Name -Site "Default Web Site" -PhysicalPath $local_unloads -ApplicationPool "DefaultAppPool" -ErrorAction Stop | Out-Null
			New-WebVirtualDirectory -Site "Default Web Site" -Application $Name -Name "DemoTickets" -PhysicalPath $local_vpath -ErrorAction Stop | Out-Null

		} -ArgumentList $Name, $local_unloads, $local_vpath
		Write-Host "The IIS Site and Virtual Directory (DemoTickets) were created on MUS1 successfully." -ForegroundColor Green
	} catch {
		Write-Host "`nFailed to create the IIS site for $Name on MUS1: $($_.Exception.Message)" -ForegroundColor Red
	}

	try {
		Write-Host "`nAttempting to create the IIS site and virtual directory on MUS2 ($mus2_ip) ..." -ForegroundColor Yellow
		Invoke-Command -ComputerName "MUS2" -Credential $Credentials -ScriptBlock {
			param($Name, $local_unloads, $local_vpath)
			New-WebApplication -Name $Name -Site "Default Web Site" -PhysicalPath $local_unloads -ApplicationPool "DefaultAppPool" -ErrorAction Stop | Out-Null
			New-WebVirtualDirectory -Site "Default Web Site" -Application $Name -Name "DemoTickets" -PhysicalPath $local_vpath -ErrorAction Stop | Out-Null

		} -ArgumentList $Name, $local_unloads, $local_vpath
		Write-Host "The IIS Site and Virtual Directory (DemoTickets) were created on MUS2 successfully." -ForegroundColor Green
	} catch {
		Write-Host "`nFailed to create the IIS site for $Name on MUS2: $($_.Exception.Message)" -ForegroundColor Red
	}


#####Modify custom.a, UNLOAD.ASP, LOOKUP.ASP, SENDDATA.BAT
	$customA = $p_vpath + "\Custom.a"
	$menuT = $p_vpath + "\menu.t"
	$sendDataFile = $p_vpath + "\SENDDATA.BAT"
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

			$content = Get-Content $customA
			
			foreach ($pair in $replacements.GetEnumerator()) {
				$content = $content -replace $pair.Key, $pair.Value
			}

			$content | Set-Content $customA

			if (Select-String -Path $customA -Pattern $LineOne) {
				Write-Host "Custom.a was successfully edited with $Name information." -ForegroundColor Green
			} else {
				Write-Host "Custom.a might not have been edited correctly." -ForegroundColor Red
			}	

		} else { 
			Write-Host "`nSum Ting Wong trying to modify the Custom.a file in the comm directory. Aborting!" -ForegroundColor Red
			throw "File not found: $customA"
			return $null
		}
	} catch {
		Write-Error $_
		return $null
	}
#SENDDATA.BAT
	try {
		if (Test-Path $sendDataFile -PathType leaf) {
			Write-Host "`nSENDDATA.BAT present. Attempting to edit with $Name info ..." -ForegroundColor Yellow

			$lines = Get-Content $sendDataFile

			$lines = $lines | ForEach-Object {
				$_.Replace($find, $Name)	
			}

			Set-Content $sendDataFile $lines

			if (Select-String -Path $sendDataFile -Pattern $find) {
				Write-Host "SENDDATA.BAT might not have been edited correctly." -ForegroundColor Red
			} else {
				Write-Host "SENDDATA.BAT was successfully edited with $Name information." -ForegroundColor Green
			}	
			
		} else {
			Write-Host "`nSum Ting Wong trying to modify the SENDDATA.BAT file in the comm directory. Aborting!"
			throw "File not found: $sendDataFile"
			return $null
		}
	} catch {
		Write-Error $_
		return $null
	}
#Unload.asp
	try {
		if (Test-Path $unloadFile -PathType leaf) {
			Write-Host "`nUnload.asp present. Attempting to edit with $Name info ... " -ForegroundColor Yellow
			
			$lines = Get-Content $unloadFile

			$lines = $lines | ForEach-Object {
				$_.Replace($find, $Name)	
			}

			Set-Content $unloadFile $lines

			if (Select-String -Path $unloadFile -Pattern $find) {
				Write-Host "Unload.asp might not have been edited correctly." -ForegroundColor Red
			} else {
				Write-Host "Unload.asp was successfully edited with $Name information." -ForegroundColor Green
			}	
		} else {
			Write-Host "`nSum Ting Wong trying to modify the Unload.asp file in the comm directory. Aborting!" -ForegroundColor Red
			throw "File not found: $unloadFile"
			return $null
		}
	} catch {
		Write-Error $_
		return $null
	}
#LOOKUP.ASP
	try {
		if (Test-Path $lookupFile -PathType leaf) {
			Write-Host "`nLOOKUP.ASP present. Attempting to modify with $Name info ..." -ForegroundColor Yellow
			
			$lines = Get-Content $lookupFile

			$lines = $lines | ForEach-Object {
				$_.Replace($find, $Name)	
			}

			Set-Content $lookupFile $lines

			if (Select-String -Path $lookupFile -Pattern $find) {
				Write-Host "LOOKUP.ASP might not have been edited correctly." -ForegroundColor Red
			} else {
				Write-Host "LOOKUP.ASP was successfully edited with $Name information." -ForegroundColor Green
			}	
		} else {
			Write-Host "`nSum Ting Wong trying to modify the LOOKUP.ASP file in the comm directory. Aborting!" -ForegroundColor Red
			throw "File not found: $lookupFile"
			return $null
		}
	} catch {
		Write-Error $_
		return $null
	}

#####Copy the modified custom.a, UNLOAD.ASP, LOOKUP.ASP, SENDDATA.BAT to the other unload server and custom.a, Menu.t the dataserver folder.
	Write-Host "`nAttempting to copy the modified files to the other unload server and dataserver..." -ForegroundColor Yellow
	
	#copy the custom.a file to O:\client\comm\ and p:\client\comm\
	Copy-Item -Path $customA -Destination $s_vpath -Force -Verbose

	#copy the sendDataFile to s:\client\comm\ and p:\client\comm\
	Copy-Item -Path $sendDataFile -Destination $s_vpath -Force -Verbose

	#copy the unloadfile to O:\ and P:\
	Copy-Item -Path $unloadFile -Destination $s_path -Force -Verbose

	#copy the lookupfile to O:\ and P:\ 
	Copy-Item -Path $lookupFile -Destination $s_path -Force -Verbose

	#copy custom.a and menu.t to the data folder on M or Y
	Copy-Item -Path $customA -Destination $the_path -Force -Verbose 
	Copy-Item -Path $menuT -Destination $the_path -Force -Verbose 

	$tp = $s_path + "\LOOKUP.ASP"
	if (Test-Path -Path $tp -PathType leaf) {
		if (Select-String -Path $tp -Pattern $find) {
			Write-Host "`nNew Parking Client $Name may not have totally been setup correctly. Check the configuration!" -ForegroundColor Red	
		} else {
			Write-Host "`nNew Clancy7 Parking Client $Name appears to be setup correctly!"	-ForegroundColor Green
		}
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
	Set-Content -Path $scriptPath -Value $scriptContent -Encoding UTF8
	Start-Process -FilePath $ps32Path -ArgumentList "-NoExit", "-File `"$scriptPath`""
}


