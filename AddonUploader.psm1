
$configName = '.upload'
$zipFileExtension = '.zip'
$tempFolderPrefix = '_upload_'
$defaultExcludes = @('.*')
$libs = 'Libs'

$apiRoot = 'https://wow.curseforge.com/api/'
$apiHeaders = @{
	"User-Agent" = "RM.AddonUploader-1.0.0";
	"X-Api-Token" = $nil
}

function Get-ObfuscatedString {
	[CmdletBinding()]
	param(
		[Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true)]
		[string] $Source,
		[Parameter(Position = 1, Mandatory = $false)]
		[string] $Key,
		[Parameter(Mandatory = $false)]
		[switch] $NoKeyOutput
	)

	$ints = $Source -split '' | ?{ $_ } | %{ [int][char]$_ }

	$max = ($ints | measure -Minimum).Minimum
	$min = ($ints | measure -Maximum).Maximum - 99

	if($min -gt $max) {
		throw "The string provided cannot be obfuscated!"
	}

	if(! $Key){
		$obfusKey = Get-Random -InputObject ($min..$max)
	}
	else {
		if($Key -match '^\d{2}$') {
			$obfusKey = [int]$Key
		}
		else {
			$obfusKey = [int][char]($Key[0])
		}
	}

	if($obfusKey -lt $min -or $obfusKey -gt $max) {
		throw "The key provided: $obfusKey must be in range $min..$max!"
	}

	$obf = -join ($ints | %{ $newInt = $_ - $obfusKey; if($newInt -lt 10) { '0' + $newInt } else {[string]$newInt} })

	if($obfusKey -lt 33) {
		$strKey = if($obfusKey -lt 10) { '0' + $obfusKey } else {[string]$obfusKey}
	}
	else {
		$strKey = [char]$obfusKey
	}

	if($NoKeyOutput) { $obf } else { "${strKey}:" + $obf }
}

function Send-AddonFile {
	[CmdletBinding()]
	param(
		[Parameter(Position = 0, Mandatory = $false)]
		[string] $InputFolder,
		[Parameter(Mandatory = $false)]
		[string] $Config,
		[Parameter(Mandatory = $false)]
		[string] $TempFolder,
		[Parameter(Mandatory = $false)]
		[string] $ZipName,
		[Parameter(Mandatory = $false)]
		[switch] $NoCleanup
	)

	if(! $Config) {
		if (! $InputFolder) {
			$InputFolder = $(Get-Item '.\').FullName
		}
		else {
			$InputFolder = Resolve-Path $InputFolder
		}
		$Config = Join-Path $InputFolder $configName
	}
	elseif(! $InputFolder) {
		$Config = Resolve-Path $Config
		$InputFolder = [System.IO.Path]::GetDirectoryName($Config)
	}
	else {
		$InputFolder = Resolve-Path $InputFolder
		$Config = Resolve-Path $Config
	}

	if(! $TempFolder) {
		$TempFolder = Join-Path ([System.IO.Path]::GetTempPath()) `
								$($tempFolderPrefix + [System.IO.Path]::GetRandomFileName())
	}

	$InputFolder = $InputFolder.TrimEnd('\', '/')

	$folderName = [System.IO.Path]::GetFileName($InputFolder)

	if(! $ZipName) {
		$ZipName = Join-Path $TempFolder ([System.IO.Path]::ChangeExtension($folderName, $zipFileExtension))
	}
	elseif([System.IO.Path]::GetExtension($ZipName) -ine $zipFileExtension) {
		$ZipName = [System.IO.Path]::ChangeExtension($ZipName, $zipFileExtension)
	}

	try {
		$cfg = Get-Content -Raw $Config | ConvertFrom-Json

		$staticCfg = Get-Content $(Join-Path $PSScriptRoot 'AddonUploader.Config.psd1') -Raw |
									Invoke-Expression
		ApplyConfig $cfg

		SetReleaseInfo $cfg.release

		$archFolder = CopySource $InputFolder $TempFolder $($defaultExcludes + $cfg.exclude)

		ReplaceContentPlaceholders $archFolder $staticCfg.ReplaceMask $cfg

		# ReplaceContentBounds

		CopyLibs $cfg.libStore $(Join-Path $archFolder $libs) $cfg.libs

		Set-Content -LiteralPath $(Join-Path $archFolder 'CHANGELOG.md') -Value $cfg.release.log -Force

		Compress-Archive $archFolder $ZipName -CompressionLevel Optimal

		$fileID = UploadArchive $InputFolder $ZipName $cfg.release

		Write-Host "File uploaded. ID = $fileID"
	}
	finally {
		if (Test-Path -LiteralPath $TempFolder -PathType Container ) {
			if ($NoCleanup) {
				Write-Host -NoNewline -ForegroundColor DarkYellow "Temp folder: "
				Write-Host -ForegroundColor Yellow $TempFolder
			}
			else {
				Write-Host -NoNewline 'Cleaning up...'
				Remove-Item -LiteralPath $TempFolder -Recurse -Force
				Write-Host -ForegroundColor DarkGreen ' DONE'
			}
		}
	}
}

<#####################################################
# Deobfuscate: function retrieves original string
# from the from the obfuscated by Get-ObfuscatedString
#####################################################>
function Deobfuscate {
	param(
		[Parameter(Position = 0, Mandatory = $true)]
		[string] $Obfuscated,
		[Parameter(Position = 1, Mandatory = $false)]
		[int] $Key
	)

	$str, $strKey = $Obfuscated -split '\:' | sort Length -Descending

	if($strKey) {
		if($strKey -match '^\d{2}$') {
			$Key = [int]$strKey
		}
		else {
			$Key = [int][char](($strKey -split '' | measure -Minimum).Minimum)
		}
	}
	elseif(! $Key) {
		throw "Deobfuscation key is not provided!"
	}

	if($str.Length % 2 -ne 0) {
		throw "Invalid string passed for deobfuscation: length must be even!"
	}

	$len = $str.Length / 2

	[string](0..$($len-1) | %{[char][int]($Key+$str.Substring($_*2,2))}) -replace ' '
}

<#######################################################
# GetValue: function retrieves value from PSCustomObject
# by its property path.
#######################################################>
function GetValue {
	param (
		[Parameter(Position = 0, Mandatory = $true)]
		[PSCustomObject] $Object, # config
		[Parameter(Position = 1, Mandatory = $true)]
		[string] $Property # config property path: 'release-version'
	)

	$Property -split '-' | % { $res = $Object } { $res = $res.$_ } { $res }
}

function ListItems {
	param (
		[Parameter(Position = 0, Mandatory = $true)]
		[string] $Path,
		[Parameter(Position = 1, Mandatory = $true)]
		[string[]] $Filters
	)

	foreach ($item in Get-ChildItem $Path) {
		if($Filters | ?{ MatchesWildcard $item $_ }) {
			$item
		}
		elseif($item.PSIsContainer) {
			ListItems $item.FullName $Filters
		}
	}
}

function MatchesWildcard($item, [string]$Wildcard) {
	if($Wildcard -match '\/|\\$' -and $item.PSIsContainer) {
		if($item.Name -ilike $Wildcard.Substring(0, $Wildcard.Length - 1)) { $true } else { $false }
	}
	elseif($item.Name -ilike $Wildcard) { $true }
	else { $false }
}

function ApplyConfig {
	param (
		[Parameter(Position = 0, Mandatory = $true)]
		[PSCustomObject] $Config
	)

	if ($Config.apiRoot) {
		$script:apiRoot = $Config.apiRoot
	}

	$script:apiHeaders['X-Api-Token'] = Deobfuscate $Config.token
}

function SetReleaseInfo {
	param (
		[Parameter(Position = 0, Mandatory = $true)]
		[PSCustomObject] $Release
	)

	$log, $version = GetLog $InputFolder

	if ($version) {
		if ($version -imatch 'alpha' -or $version -imatch 'test') {
			$type = 'alpha'
		}
		elseif ($version -imatch 'beta') {
			$type = 'beta'
		}
		else {
			$type = 'release'
		}

		$Release.version = $version
		$Release.type = $type
		$Release.log = $($log -replace "`n`n","`n").Trim()
	}
}

<##########################################
# CopySource: function creates temp folder,
# copies addon source folder into it
# and removes redundand files/folder.
##########################################>
function CopySource {
	param (
		[Parameter(Position = 0, Mandatory = $true)]
		[string] $InputFolder,
		[Parameter(Position = 1, Mandatory = $true)]
		[string] $TempFolder,
		[Parameter(Position = 2, Mandatory = $false)]
		[string[]] $Excludes = $defaultExcludes
	)

	$folderName = [System.IO.Path]::GetFileName($InputFolder)
	$archFolder = Join-Path $TempFolder $folderName

	if (Test-Path $TempFolder -PathType Container) {
		Remove-Item $TempFolder -Recurse -Force
	}

	New-Item $TempFolder -ItemType Directory -Force | Out-Null

	Copy-Item -LiteralPath $InputFolder -Destination $TempFolder -Recurse -Container -Exclude $Excludes

	ListItems $archFolder $Excludes | Remove-Item -Recurse -Force

	$archFolder
}

function CopyLibs {
	param(
		[Parameter(Position = 0, Mandatory = $true)]
		[string] $Store,
		[Parameter(Position = 1, Mandatory = $true)]
		[string] $Target,
		[Parameter(Position = 2, Mandatory = $false)]
		[string[]] $Libs = @()
	)

	$libs | % {
		$libPath = Join-Path $Store $_
		Copy-Item -LiteralPath $libPath -Destination $Target -Recurse -Container
	}
}

function ReplaceContentPlaceholders {
	param (
		[Parameter(Position = 0, Mandatory = $true)]
		[string] $Folder,
		[Parameter(Position = 1, Mandatory = $true)]
		[string[]] $Mask,
		[Parameter(Position = 2, Mandatory = $true)]
		[PSCustomObject] $Config
	)

	$re = [regex]'@@([\w-]+)@@'

	Get-ChildItem -Path $(Join-Path $Folder '*') -Include $Mask -Recurse | % {
		$file = $_
		Write-Host "Replacing in $($file.Name):"
		$content = Get-Content $file -Raw
		$content = $re.Replace($content, {
			param($match)
			$prop = $match.Groups[1].Value
			$replacement = GetValue $Config $prop
			if ($replacement) {
				Write-Host "\-$prop -> $replacement"
				$replacement
			}
			else {
				Write-Host -ForegroundColor DarkRed "$prop is not set"
				"\-[PropertyError: '$prop']"
			}
		})
		Set-Content -LiteralPath $file -Value $content -Force
	}
}

function ParseTagRefs([string] $refs) {
	[string]($refs | Select-String 'tag:\s*([\w-.]+),' -AllMatches | %{$_.matches} | %{ $_.Groups[1].Value} | sort | select -Last 1)
}

<################################################
# GetLog: function gets git log (change log)
# and last ersion from tag or commit hash
# from the git repo in the folder as markdown
################################################>
function GetLog {
	param(
		[Parameter(Position = 0, Mandatory = $true)]
		[string] $GitFolder
	)

	try {
		Push-Location $GitFolder

		$lastVersion = $null
		$lines = 5
		$log = & git log --tags --pretty=format:"%aI|%D|%h|%s|%b" 2>&1 | %{ $_ -split '\|' }

		if($?) {
			( (0..$($log.Length/$lines - 1)) |
				%{ [pscustomobject] @{ date=[DateTime]::Parse($log[$_*$lines]); `
										version=$(ParseTagRefs $log[$_*$lines + 1]); `
										hash=$log[$_*$lines + 2]; title=$log[$_*$lines + 3]; `
										description=$log[$_*$lines + 4] } } |
				Group-Object -Property @{Expression = {$_.date.Date}}, version |
				Sort-Object -Property @{Expression = {$_.Values[0]}; Descending = $true}, @{Expression = {$_.Values[1]}} | % {
					$group = $_
					$dateStr = $group.Values[0].ToString('dd.MM.yyyy')
					$verStr = $group.Values[1]
					if ($verStr) {
						if (! $lastVersion) {
							$lastVersion = $verStr
						}
						$verStr = ' - ver. ' + $verStr
					}
					$group.Group | % {
						$lines = "##### $dateStr$verStr`n"
					}{
						if (! $lastVersion) {
							$lastVersion = 'test-' + $_.hash
						}
						$lines+="###### $($_.title)`n$($_.description)`n"
					}{
						-join $lines
					}
				} ) -join "-----`n"
				$lastVersion
		}
		else {
			"###### Cannot get changelog:`n$log"
			$lastVersion
		}
	}
	finally {
		Pop-Location
	}
}

function GetGameVersionIDs {
	param (
		[Parameter(Position = 0, Mandatory = $false, ValueFromPipeline = $true)]
		[string[]] $Versions
	)

	$resp = Invoke-RestMethod "${script:apiRoot}game/versions" -Method Get `
				-Headers $script:apiHeaders

	if ($Versions) {
		$resp | ?{ $Versions.Contains($_.name) } | %{ $_.id }
	}
	else {
		$resp | select -last 3 | %{ $_.id }
	}
}

function UploadArchive {
	param (
		[Parameter(Position = 0, Mandatory = $true)]
		[string] $InputFolder,
		[Parameter(Position = 1, Mandatory = $true)]
		[string] $ZipFile,
		[Parameter(Position = 2, Mandatory = $true)]
		[PSCustomObject] $Release
	)

	$gameVersionIDs = GetGameVersionIDs $Release.gameVersions

	$metadata = [PSCustomObject] @{
		changelog = $Release.log;
		changelogType = 'markdown';
		displayName = $Release.version;
		releaseType = $Release.type;
		gameVersions = $gameVersionIDs;
	}

	$form = @{
		metadata = $metadata | ConvertTo-Json -Compress;
		file = Get-Item -Path $ZipFile
	}

	$response = Invoke-RestMethod "${script:apiRoot}projects/$($Release.projectID)/upload-file" `
					-Method Post -Headers $script:apiHeaders -Form $form
	$response.id
}
