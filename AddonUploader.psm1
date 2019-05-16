$default = @{
    
}

$configName = '.config'

$apiRoot = 'https://wow.curseforge.com/api/'

$zipFileExtension = '.zip'

function Get-ObfuscatedString {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Source,
        [Parameter(Position = 1, Mandatory = $false)]
        [string]$Key,
        [Parameter(Mandatory = $false)]
        [switch]$NoKeyOutput
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
        [string]$InputFolder = $(Get-Item '.\').FullName,
        [Parameter(Mandatory = $false)]
        [string]$Config,
        [Parameter(Mandatory = $false)]
        [string]$TempFolder = $([System.IO.Path]::GetTempFileName()),
        [Parameter(Mandatory = $false)]
        [string]$ZipName,
        [Parameter(Mandatory = $false)]
        [int]$Key
    )

    if(! $Config) {
        $Config = [System.IO.Path]::Combine($InputFolder, $configName)
    }
    elseif(! $InputFolder) {
        $InputFolder = [System.IO.Path]::GetDirectoryName($Config)
    }
    
    if(! $ZipName) {
        $ZipName = [System.IO.Path]::Combine($TempFolder, [System.IO.Path]::ChangeExtension([System.IO.Path]::GetFileName($InputFolder), $zipFileExtension))
    }
    elseif([System.IO.Path]::GetExtension($ZipName) -ine $zipFileExtension) {
        $ZipName = [System.IO.Path]::ChangeExtension($ZipName, $zipFileExtension)
    }

    echo $InputFolder
    echo $Config
    echo $TempFolder
    echo $ZipName
    echo $Key

    #GetLog $InputFolder | Write-Host
    #Deobfuscate $TempFolder $Key | Write-Host
}

<################################################
# GetLog: function gets git log (change log)
# from the git repo in the folder as markdown
################################################>
function GetLog {
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [string]$GitFolder
    )

    Try {
        Push-Location $GitFolder

        $lines = 4
        $log = git log --pretty=format:"%aI|%an|%s|%b" | %{ $_ -split '\|' }
        ( (0..$($log.Length/$lines - 1)) |
            %{ [pscustomobject] @{ date=[DateTime]::Parse($log[$_*$lines]); author=$log[$_*$lines + 1]; title=$log[$_*$lines + 2]; description=$log[$_*$lines + 3] } } |
            Group-Object -Property @{Expression = {$_.date.Date}}, author |
            Sort-Object -Property @{Expression = {$_.Values[0]}; Descending = $true}, @{Expression = {$_.Values[1]}} | %{
                $group = $_
                $group.Group | % {$lines = "##### $($group.Values[0].ToString('dd.MM.yyyy')) - $($group.Values[1])`n"}{$lines+="###### $($_.title)`n$($_.description)`n`n"}{-join $lines}
            } ) -join "-----`n"
    }
    Finally {
        Pop-Location
    }
}

<#####################################################
# Deobfuscate: function retrieves original string
# from the from the obfuscated by Get-ObfuscatedString
#####################################################>
function Deobfuscate {
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [string]$Obfuscated,
        [Parameter(Position = 1, Mandatory = $false)]
        [int]$key
    )

    $str, $strKey = $Obfuscated -split '\:' | sort Length -Descending

    if($strKey) {
        if($strKey -match '^\d{2}$') {
            $key = [int]$strKey
        }
        else {
            $key = [int][char](($strKey -split '' | measure -Minimum).Minimum)
        }
    }
    elseif(! $key) {
        throw "Deobfuscation key is not provided!"
    }

    if($str.Length % 2 -ne 0) {
        throw "Invalid string passed for deobfuscation: length must be even!"
    }

    $len = $str.Length / 2

    [string](0..$($len-1) | %{[char][int]($key+$str.Substring($_*2,2))}) -replace ' '
}
