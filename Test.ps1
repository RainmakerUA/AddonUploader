Remove-Module AddonUploader

#Set-Location D:\DEV\Lua\XPMultiBar
Import-Module ..\AddonUploader
Update-Localization -InputFolder D:\DEV\Lua\TooltipUpgrades -SourceMask main.lua
#Send-AddonFile #..\Lua\XPMultiBar\ #-TempFolder E:\Temp
#Send-AddonFile ..\Lua\XPMultiBar\
#Send-AddonFile -Config ..\Lua\XPMultiBar\.upload
#Send-AddonFile ..\Lua\ManaCostPerc\ -Config ..\Lua\XPMultiBar\.upload
