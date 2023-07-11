$IsDotSourced = $MyInvocation.InvocationName -eq '.' -or $MyInvocation.Line -eq ''
$DefaultTextColor = (Get-Host).UI.RawUI.ForegroundColor
$SearchAttemptsUsed = 0



#region General use
function Confirm-EmptyVariable($Variable)
{
	return $null -eq $Variable -or $Variable -eq ''
}

function Set-Title()
{
	$Host.UI.RawUI.WindowTitle = 'Mod.IO Downloader'
}

function Exit-WithMessageAndPause()
{
    Write-Host "The script will now exit."
    pause
    if ($IsDotSourced)
    {
        return
    }
	exit
}

function Test-RequiredModule([string]$Module)
{
    if (Get-Module -ListAvailable -Name $Module)
    {
        return
    }

    Write-Host "The module " -NoNewline
    Write-Host "$Module" -ForegroundColor Green -NoNewline 
    Write-Host " does not exist!"
    Write-Host "This is needed for the script to run. Do you want to install it?"
    Write-Host "Type " -NoNewline
    Write-Host "Y " -ForegroundColor Yellow -NoNewline
    Write-Host "or " -NoNewline
    Write-Host "N" -ForegroundColor Yellow -NoNewline
    Write-Host ", then press " -NoNewline
    Write-Host "ENTER" -ForegroundColor Cyan -NoNewline
    Write-Host ": " -NoNewline
    $Prompt = Read-Host
    if ($Prompt -ne "y")
    {
        Exit-WithMessageAndPause
    }
    $OldErrorActionPreference = $ErrorActionPreference
    Install-Module $Module -Scope CurrentUser
    if (!$?)
    {
        Write-Host "An error occurred! " -ForegroundColor Red -NoNewline
        Write-Host " You may need to run PowerShell in administrator mode to install the module ""$Module""."
        pause
        exit
    }
    else
    {
        Write-Host "Done! Module """ -NoNewline
        Write-Host "$Module" -ForegroundColor Green -NoNewline
        Write-Host """ should have been installed for the current user!"
        pause
    }
    $ErrorActionPreference = $OldErrorActionPreference
    Clear-Host
}

function Get-ScriptConfigOptions()
{
	[system.gc]::Collect()

    $FileName = $PSCommandPath.Split("\")[-1]
    $FileNameNoext = $FileName.SubString(0, $FileName.Length - 4)
	$Global:ScriptConfigFileName = "$FileNameNoExt.conf"
	if (!(Test-Path $Global:ScriptConfigFileName))
	{
		$DownloadsFolderLocation = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path
		New-Item $Global:ScriptConfigFileName | Out-Null
		Set-Content $Global:ScriptConfigFileName "ApiKey=put-api-key-here`nDownloadLocation=$DownloadsFolderLocation`nModSearchAttempts=5"
	}
	foreach ($Line in (Get-Content $Global:ScriptConfigFileName))
	{
		if (Confirm-EmptyVariable $Line)
		{
			continue
		}

		$LineSplit = $Line.Split("=")
		$OptionName = $LineSplit[0]
		$OptionResult = $LineSplit[1].Split("#")[0].Trim() # The extra functions remove the comments found in the conf file by default
		Set-Variable $OptionName $OptionResult -Scope Global
		if ($OptionName -eq "ApiKey" -and $OptionResult -eq "put-api-key-here")
		{
			Write-Color "ERROR! ","The ","default value ","for the API key is still in the config file! Please change it to your own." Red,$DefaultTextColor,Yellow,$DefaultTextColor
			Exit-WithMessageAndPause
			return
		}
		if ($OptionName -eq "DownloadLocation")
		{
			if (!(Test-Path $Global:DownloadLocation))
			{
				Write-Color "ERROR! ","The download location ",$Global:DownloadLocation," is invalid! Please provide a path to an existing folder, or make the folder at the path provided." Red,$DefaultTextColor,Yellow,$DefaultTextColor
				Exit-WithMessageAndPause
				return
			}
		}
		if ($IsDotSourced)
		{
			Write-Host "The config option ""$OptionName"" is ""$OptionResult"""
		}
	}
}

function Start-YesOrNoPrompt([string]$Question = 'Agree?', [string]$YesDescription = 'Yes', [string]$NoDescription = 'No', [string]$DefaultOptionStr = 'Yes')
{
	switch ($DefaultOptionStr)
	{
		'Yes'
		{
			$DefaultOptionInt = 0
		}
		'No'
		{
			$DefaultOptionInt = 1
		}
	}
	$Choices = @(
		[System.Management.Automation.Host.ChoiceDescription]::New("&Yes", $YesDescription)
		[System.Management.Automation.Host.ChoiceDescription]::New("&No", $NoDescription)
	)
	return ![bool]$Host.UI.PromptForChoice('', $Question, $Choices, $DefaultOptionInt)
}
#endregion

#region Downloading process
function Test-ApiKey()
{
	Write-Color "Testing the provided ","API key","..." $DefaultTextColor,Yellow,$DefaultTextColor
	try
	{
		Invoke-RestMethod -Method Get -Uri "https://api.mod.io/v1/games?api_key=$Global:ApiKey" | Out-Null
	}
	catch
	{
		if ($null -eq $_.ErrorDetails.Message)
		{
			Write-Color "The provided API key is ","valid","!" $DefaultTextColor,Green,$DefaultTextColor
			return
		}
		$ErrorCode = (($_.ErrorDetails.Message) | ConvertFrom-Json).error.error_ref
		switch ($ErrorCode)
		{
			{$_ -in 11000..11002}
			{
				Write-Color "ERROR! ","Your API key is " Red,$DefaultTextColor -NoNewLine
			}
			11000
			{
				Write-Color "missing","! Please provide your own API key." Red,$DefaultTextColor
			}
			11001
			{
				Write-Color "malformed","! Please make sure you put in your API key correctly." Red,$DefaultTextColor
			}
			11002
			{
				Write-Color "invalid","! Please provide a new API key for your account." Red,$DefaultTextColor
			}
			default
			{
				Write-Color "ERROR! ","The error code is ",$ErrorCode Red,$DefaultTextColor,Yellow
			}
		}
		Exit-WithMessageAndPause
		return
	}
	Write-Color "The provided API key is ","valid","!" $DefaultTextColor,Green,$DefaultTextColor
	return
}

function Get-URLs()
{
	[system.gc]::Collect()

	$Global:UrlSet = Read-Host "Paste in the URLs of the mod(s) you'd like to download. If you have multiple URLs, split each one with a comma and no spaces"
	if ($UrlSet.Contains(",")) # Multiple URLs provided
	{
		$Global:UrlArray = $UrlSet.Split(",")
		$Global:IsUrlSetMultiple = $true
		$Global:IsUrlSetMultiple > $null

		$HasValidUrl = $false
		foreach ($Url in $Global:UrlArray)
		{
			if ($Url.Contains("mod.io"))
			{
				$HasValidUrl = $true
				break
			}
		}
		if (!$HasValidUrl)
		{
			Clear-Host
			Write-Host "No mod.io URLs provided!" -ForegroundColor Red
			Get-URLs
		}
	}
	else
	{
		$Global:IsUrlSetMultiple = $false
		if (!$UrlSet.Contains("mod.io"))
		{
			Clear-Host
			Write-Host "That was not a valid mod.io URL!" -ForegroundColor Red
			Get-URLs
		}
		else
		{
			Clear-Host
			$Global:Url = $Global:UrlSet
		}
	}
}

function Get-GameNameIdFromUrl([string]$Url)
{
	return $Url.Split("/")[4]
}

function Get-ModNameIdFromUrl([string]$Url)
{
	return $Url.Split("/")[-1]
}

function Get-GameIdFromUrl([string]$Url)
{
	[system.gc]::Collect()

	Write-Color "Getting the ","game ID","..." $DefaultTextColor,Green,$DefaultTextColor
	$ModIoData = (Invoke-RestMethod -Method Get -Uri "https://api.mod.io/v1/games?api_key=$ApiKey").data
	if (Confirm-EmptyVariable $ModIoData)
	{
		Write-Color "ERROR! ","Could not get mod.io data! The API key provided may no longer work!" Red,$DefaultTextColor
		Exit-WithMessageAndPause
		return
	}

	foreach ($SetOfData in $ModIoData)
	{
		if ($SetOfData.name_id -eq (Get-GameNameIdFromUrl($Url)))
		{
			return $SetOfData.id
		}
	}
	Write-Color "Could not get the ","game ID ","from the URL ",$Url,"!" $DefaultTextColor,Green,$DefaultTextColor,Yellow,$DefaultTextColor
	Exit-WithMessageAndPause
	return
}

function Get-ModIdFromUrlAndGameId([string]$Url, [int]$GameId, [int]$ResultsOffset = 0)
{
	[system.gc]::Collect()

	$ModNameId = Get-ModNameIdFromUrl $Url
	$CurrentAttemptNum = $Global:SearchAttemptsUsed + 1
	Write-Color "Searching mod.io for the mod ID (","Attempt $CurrentAttemptNum",")" $DefaultTextColor,Yellow,$DefaultTextColor
	$ModIoGameData = (Invoke-RestMethod -Method Get -Uri "https://api.mod.io/v1/games/$GameId/mods?api_key=$ApiKey&_offset=$ResultsOffset&_q=$ModNameId").data

	foreach ($SetOfData in $ModIoGameData)
	{
		if ($SetOfData.profile_url -eq $Url)
		{
			return $SetOfData.id
		}
	}
	$Global:SearchAttemptsUsed += 1
	if ($Global:SearchAttemptsUsed -eq $Global:ModSearchAttempts)
	{
		Write-Color "Could not get the ","mod ID ","from the URL ",$Url," in ",$Global:ModSearchAttempts," attempts!" $DefaultTextColor,Green,$DefaultTextColor,Yellow,$DefaultTextColor,Yellow,$DefaultTextColor
		Write-Color "Continue searching for another ",$Global:ModSearchAttempts," attempts?" $DefaultTextColor,Green,$DefaultTextColor
		switch (Start-YesOrNoPrompt -Question '' -YesDescription "Continue searching for 10 more attempts." -NoDescription "Do not continue searching, and exit the script.")
		{
			$false
			{
				Exit-WithMessageAndPause
				return
			}
			$true
			{
				$Global:SearchAttemptsUsed = 0
			}
		}
	}
	Get-ModIdFromUrl $Url $GameId ($ResultsOffset + $ModIoGameData.Length)
}

function Get-ModZipFileFromUrl([string]$Url)
{
	[system.gc]::Collect()

	Write-Color "Processing ",$Url,"..." $DefaultTextColor,Green,$DefaultTextColor
	$GameId = Get-GameIdFromUrl $Url
	if (Confirm-EmptyVariable $GameId)
	{
		return
	}
	$ModId = Get-ModIdFromUrlAndGameId $Url $GameId

	$ModData = (Invoke-RestMethod -Method Get -Uri "https://api.mod.io/v1/games/$GameId/mods/$ModId`?api_key=$ApiKey")
	$DownloadUrl = $ModData.modfile.download.binary_url
	$DownloadFileName = $ModData.modfile.filename
	if (Test-Path "$Global:DownloadLocation\$DownloadFileName")
	{
		Write-Color "WARNING! ","The file ",$DownloadFileName," has already been downloaded!" Yellow,$DefaultTextColor,Green,$DefaultTextColor
		switch (Start-YesOrNoPrompt -Question 'Do you want to replace the file?' -YesDescription 'The file will be removed before being downloaded.' -NoDescription 'The script will skip this file.')
		{
			$true
			{
				Remove-Item "$Global:DownloadLocation\$DownloadFileName"
			}
			$false
			{
				return
			}
		}
	}
	Write-Color "Downloading ",$DownloadFileName," to ",$Global:DownloadLocation,"..." $DefaultTextColor,Green,$DefaultTextColor,Green,$DefaultTextColor
	Invoke-WebRequest $DownloadUrl -OutFile "$Global:DownloadLocation\$DownloadFileName"
}
#endregion



if (!$IsDotSourced)
{
	Set-Title
	Test-RequiredModule "PSWriteColor"
	Get-ScriptConfigOptions
	Test-ApiKey

	Get-URLs
	if ($Global:IsUrlSetMultiple)
	{
		foreach ($Url in $Global:UrlArray)
		{
			Get-ModZipFileFromUrl $Url
		}
		Write-Host "Done!" -ForegroundColor Green
		Exit-WithMessageAndPause
	}
	Get-ModZipFileFromUrl $Global:Url
	Write-Host "Done!" -ForegroundColor Green
	Exit-WithMessageAndPause
}