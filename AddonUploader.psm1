
$localeDirName = "Locales"
$localeFormat = 'locale-{0}.lua'
$trueParam = ', true'
$loc_re = '(?:(?<=[\s\(\[])L(?<br>\[)?\"(?<str>(?:\\.|[^"])*)\"(?(br)\]|))'
$ext_re = '^[A-Z0-9._]+$'
$old_re = '(?m)^L\["([^"]+?)"\]\s*=\s*"([^"]+?)"'

$configName = '.upload'
$tokenFile = '.token'
$zipFileExtension = '.zip'
$tempFolderPrefix = '_upload_'
$libs = 'Libs'

$apiRoot = 'https://wow.curseforge.com/api/'
$apiHeaders = @{
	"User-Agent" = "RM.AddonUploader-1.0.0";
	"X-Api-Token" = $nil
}

function Update-Localization {
	[CmdletBinding()]
	param (
		[Parameter(Position = 0, Mandatory = $false)]
		[string] $InputFolder,
		[Parameter(Position = 1, Mandatory = $false)]
		[string] $SourceMask,
		[Parameter(Position = 2, Mandatory = $false)]
		[string[]] $Locales,
		[Parameter(Position = 3, Mandatory = $false)]
		[string] $BaseLocale
	)

	if (! $InputFolder) {
		$InputFolder = $(Get-Item '.\').FullName
	}
	else {
		$InputFolder = Resolve-Path $InputFolder
	}

	$localeDir = Join-Path $InputFolder $script:localeDirName

	if (! $SourceMask) {
		$SourceMask = "*.lua"
	}

	if (! $Locales) {
		$localePattern = '^' + $($script:localeFormat -f '([a-zA-Z]{4})\') + '$'
		$Locales = Get-ChildItem $(Join-Path $localeDir $($script:localeFormat -f '*')) | %{ $_.Name } `
					| Select-String -Pattern $localePattern `
					| %{ $_.Matches.Groups[1].Value }
	}

	if (! $Locales) {
		$Locales = @('enUS', 'ruRU')
	}

	if (! $BaseLocale -or ! $Locales.Contains($BaseLocale)) {
		$BaseLocale = $Locales[0]
	}

	$localeHeaderFmt = "-- This file is generated with $($MyInvocation.MyCommand.ModuleName)::$($MyInvocation.MyCommand.Name)
local addonName = ...
local L = LibStub(`"AceLocale-3.0`"):NewLocale(addonName, `"{0}`"{1})
if not L then return end
---------- Total: {2} ----------"
	$localeSources = Get-ChildItem $(Join-Path $InputFolder $SourceMask) -Recurse
	$locStrings = $localeSources | %{ $strings = @() } `
									{ $strings += ((Select-String -Path $_ -Encoding utf8 -Pattern $script:loc_re -CaseSensitive -AllMatches).Matches | ?{ $_ } | %{ $_.Groups['str'].Value } ) } `
									{ $strings } | Select-Object -Unique

	$total = $locStrings.Length
	$ext_strings = $locStrings | ?{ $_ -cmatch $script:ext_re }
	$strings = $locStrings | ?{ $_ -cnotmatch $script:ext_re }

	$Locales | %{
		$locale = $_
		$oldFile = Join-Path $localeDir "locale-$locale.lua"
		$file = "$oldFile.new"
		$oldStrings = @{ }
  
		if (Test-Path -LiteralPath $oldFile -PathType Leaf) {
			Select-String -Path $oldFile -Encoding utf8 -Pattern $script:old_re `
					| %{ } { $_.Matches | %{ $oldStrings[$_.Groups[1].Value] = $_.Groups[2].Value } } {$oldStrings} `
					| Out-Null
		}

		Set-Content $file ([string]::Format($localeHeaderFmt, $locale, $(if($locale -eq $BaseLocale){ $script:trueParam } else { "" }), $total))

		@($strings, $ext_strings) | %{
			Add-Content $file ($_ | %{ if($locale -eq $BaseLocale -and ! $oldStrings[$_]){ "L[`"$_`"] = true" } else { "L[`"{0}`"] = `"{1}`"" -f $_, $(if($oldStrings[$_]) { $oldStrings[$_] } else { $_ }) } })
		}
	}
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

	$measures = $Source -split '' | ?{ $_ } | %{ [int][char]$_ } | measure -Minimum -Maximum

	$max = $measures.Minimum
	$min = $measures.Maximum - 99

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

function Publish-AddonFile {
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
		[switch] $NoUpload,
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
		$TempFolder = Join-Path ([System.IO.Path]::GetTempPath()) $($tempFolderPrefix + [System.IO.Path]::GetRandomFileName())
	}

	$InputFolder = $InputFolder.TrimEnd('\', '/')

	try {
		$cfg = Get-Content -Raw $Config | ConvertFrom-Json
		$staticCfg = Get-Content $(Join-Path $PSScriptRoot 'AddonUploader.Config.psd1') -Raw | Invoke-Expression

		ApplyConfig $staticCfg

		SetReleaseInfo $cfg.release

		$whatsnewPath = Join-Path $InputFolder 'WhatsNew.md'

		if (Test-Path -LiteralPath $whatsnewPath) {
			$whatsnew = Get-Content $whatsnewPath -Raw
			$cfg.release.log = $whatsnew + "`n" + $cfg.release.log
		}

		$archFolder = CopySource $InputFolder $TempFolder $($staticCfg.Excludes + $cfg.exclude)

		ReplaceContentPlaceholders $archFolder $staticCfg.ReplaceMask $cfg

		ReplaceContentBounds $archFolder $staticCfg $cfg.release.type

		CopyLibs $staticCfg.libStore $(Join-Path $archFolder $libs) $cfg.libs

		Set-Content -LiteralPath $(Join-Path $archFolder 'CHANGELOG.md') -Value $cfg.release.log -Force

		if(! $ZipName) {
			$folderName = [System.IO.Path]::GetFileName($InputFolder)
			$ZipName = Join-Path $TempFolder "$folderName-$($cfg.release.version)$zipFileExtension"
		}
		elseif([System.IO.Path]::GetExtension($ZipName) -ine $zipFileExtension) {
			$ZipName = [System.IO.Path]::ChangeExtension($ZipName, $zipFileExtension)
		}

		Compress-Archive $archFolder $ZipName -CompressionLevel Optimal

		if ($NoUpload) {
			Write-Host "File uploading skipped."
		}
		else {
			$fileID = UploadArchive $InputFolder $ZipName $cfg
			Write-Host "File uploaded. ID = $fileID"
		}
	}
	finally {
		if (Test-Path -LiteralPath $TempFolder -PathType Container) {
			if ($NoCleanup) {
				Write-Host -NoNewline -ForegroundColor DarkYellow "Temp folder left: "
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

function GetToken([string] $tokenFile) {
	if (! $tokenFile) {
		$tokenFile = $script:tokenFile
	}

	if (! [IO.Path]::IsPathRooted($tokenFile)) {
		$tokenFile = $(Join-Path $PSScriptRoot $tokenFile)
	}

	if (! (Test-Path -PathType Leaf -Path $tokenFile)) {
		throw "Token file $tokenFile was not found!"
	}

	Deobfuscate $(Get-Content $tokenFile)
}

function ApplyConfig {
	param (
		[Parameter(Position = 0, Mandatory = $true)]
		[PSCustomObject] $StaticConfig
	)

	if ($StaticConfig.ApiRoot) {
		$script:apiRoot = $StaticConfig.ApiRoot
	}

	$script:apiHeaders['X-Api-Token'] = GetToken $StaticConfig.TokenFile
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
		$Release.date = [datetime]::Today.ToString('yyyyMMdd')
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

	$archLibs = New-Item $Target -ItemType Directory -Force | Out-Null

	$libs | % {
		$libPath = Join-Path $Store $_
		#Write-Host -NoNewline "Copy lib $libPath -> $Target ..."
		Copy-Item -LiteralPath $libPath -Destination $Target -Recurse -Container #-Verbose
		#Write-Host -ForegroundColor DarkGreen ' DONE'
	}

	$archLibs.FullName
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
				"[PropertyError: '$prop']"
			}
		})
		Set-Content -LiteralPath $file -Value $content -NoNewline -Force
	}
}

function ReplaceContentBounds([string] $folder, [hashtable] $cfg, [string] $releaseType) {
	ListItems $folder $cfg.ReplaceMask | % {
		$file = $_
		$extension = $(Split-Path $file -Extension)
		$replaces = $cfg.Replace.$extension

		if ($replaces) {
			$replaces | ? { ! $_.Types -or $_.Types -contains $releaseType } | % { ApplyReplacement $file.FullName $_ }
		}
	}
}

function ApplyReplacement([string] $filename, [hashtable] $replacement) {
    Write-Debug "Replacing bounds in '$filename'"
	$startFrom = $replacement.Start[0]
	$startTo = $replacement.Start[1]
	$endFrom = $replacement.End[0]
	$endTo = $replacement.End[1]
	$remove = $replacement.RemoveBetween
	$prefix = $replacement.PrefixBetween

	$lines = Get-Content -LiteralPath $filename
	$replaced = @()
	$inside = $false

	foreach ($line in $lines) {
		if ($line.Contains($startFrom)) {
			if ($startTo) {
                Write-Debug "Replacing '$startFrom' -> '$startTo'"
				$replaced += $($line -replace $startFrom,$startTo)
			}
			$inside = $true
		} elseif ($line.Contains($endFrom)) {
			if ($endTo) {
                Write-Debug "Replacing '$endFrom' -> '$endTo'"
				$replaced += $($line -replace $endFrom, $endTo)
			}
			$inside = $false
		} elseif ($inside -and $prefix) {
            Write-Debug "Prefixing with '$prefix'"
			$replaced += ($prefix + $line)
		} elseif (! $inside -or ! $remove) {
            Write-Verbose "Copy line to resulting file"
			$replaced += $line
		} else {
            Write-Debug "Skip line"
        }
	}

	Set-Content -LiteralPath $filename -Value $replaced -Force
}

function ParseTagRefs([string] $refs) {
	[string]($refs | Select-String 'tag:\s*([\w-.]+)' -AllMatches | % { $_.matches } | % { $_.Groups[1].Value } | sort | select -Last 1)
}

<################################################
# GetLog: function gets git log (change log)
# and last version from tag or commit hash
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
		$branch = & git branch | ? { $_.StartsWith('*') } | % { $_.Substring(2) } | Select-Object -First 1
		$log = & git log $branch --pretty=format:"%aI|%D|%h|%B" 2>&1 | %{ $_ -split '\|' }

		if($?) {
			$mode = 0
			$logEntries = @()
			$date = $null
			$version = $null
			$hash = $null
			$title = $null
			$description = $null
			for ($line = 0; $line -lt $log.Count; $line++) {
				$currentLine = $log[$line]
				$newDate = [DateTime]::MinValue

				if (($mode -eq 0 -or $mode -gt 4) -and [DateTime]::TryParse($currentLine, [ref]$newDate) ) {
					if ($date) {
						$logEntries += [pscustomobject] @{
							date = $date; version = $version; hash = $hash; `
							title = $title; description = $description
						}
						$date = $null
						$version = $null
						$hash = $null
						$title = $null
						$description = $null
					}
					$mode = 0
				}

				switch ($mode) {
					0 { $date = $newDate; $mode++; break }
					1 { $version = $(ParseTagRefs $currentLine); $mode++; break }
					2 { $hash = $currentLine; $mode++; break }
					3 { $title = $currentLine; $mode++; break }
					4 {
						if ($currentLine) {
							$title += '|' + $currentLine
						}
						else {
							$mode++
						}
						break
					}
					5 {
						if ($description) {
							$description += '|' + $currentLine
						}
						else {
							$description = $currentLine
						}
					}
					default { Write-Warning " *** Unexpected mode: $mode at line: $currentLine" }
				}
			}

			($logEntries |
				? { $_.title -inotmatch '^merge' -or $_.version } |
				Group-Object -Property @{ Expression = { $_.date.Date } } |
				Sort-Object -Property @{ Expression = { $_.Values[0] }; Descending = $true } |
				% {
					$group = $_
					$dateStr = $group.Values[0].ToString('dd.MM.yyyy')
					$verStr = ""
					$group.Group | % {
						$lines = ""
					} {
						# TODO: Support for untagged commit after a tag on the same date
						if (! $verStr) {
							$verStr = if ($_.version) { $_.version } else { "-" }
						}
						if (! $lastVersion) {
							$lastVersion = if ($verStr -ne "-") { $verStr } else { 'test-' + $_.hash }
						}
						if (! $lines) {
							$lines = if ($verStr -ne "-") { "##### $dateStr - ver. $verStr`n" } else { "##### $dateStr`n" }
						}
						$titles = ($_.title -split '\|' | % { '###### ' + $_ }) -join "`n"
						$descriptions = $_.description -replace '\|', "`n"
						$lines += "$titles`n$descriptions`n"
					} {
						-join $lines
					}
				}) -join "-----`n"

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

	$resp = Invoke-RestMethod "${script:apiRoot}game/versions" -Method Get -Headers $script:apiHeaders

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
		[PSCustomObject] $Cfg
	)

	$gameVersionIDs = GetGameVersionIDs $Cfg.release.gameVersions

	if ($gameVersionIDs.Count -eq 1) {
		$gameVersionIDs = @($gameVersionIDs)
	}

	$metadata = [PSCustomObject] @{
		changelog = $Cfg.release.log;
		changelogType = 'markdown';
		displayName = $Cfg.release.version;
		releaseType = $Cfg.release.type;
		gameVersions = $gameVersionIDs;
	}

	$form = @{
		metadata = $metadata | ConvertTo-Json -Compress;
		file = Get-Item -Path $ZipFile
	}

	$response = Invoke-RestMethod "${script:apiRoot}projects/$($Cfg.projectID)/upload-file" `
					-Method Post -Headers $script:apiHeaders -Form $form
	$response.id
}
