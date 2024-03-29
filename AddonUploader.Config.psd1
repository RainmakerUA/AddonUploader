
@{
	ApiRoot = 'https://wow.curseforge.com/api/';
	TokenFile = 'curseforge.token';
	Excludes = @('.*');
	LibStore = 'D:\DEV\Lua\!Libs';
	ReplaceMask = @('*.lua', '*.toc', '*.xml');
	Replace = @{
		'.lua' = @(
			@{
				Start = @('--@debug@', '--[===[@debug@');
				End = @('--@end-debug@', '--@end-debug@]===]');
			},
			@{
				Start = @('--[===[@non-debug@', '--@non-debug@');
				End = @('--@end-non-debug@]===]', '--@end-non-debug@');
			},
			@{
				Start = @('--@do-not-package@', '');
				End = @('--@end-do-not-package@', '');
				RemoveBetween = $true;
			},
			@{
				Start = @('--@alpha@', '--[===[@alpha@');
				End = @('--@end-alpha@', '--@end-alpha@]===]');
				Types = @('alpha');
			},
			@{
				Start = @('--[===[@non-alpha@', '--@non-alpha@');
				End = @('--@end-non-alpha@]===]', '--@end-non-alpha@');
				Types = @('alpha');
			}
		);
		'.toc' = @(
			@{
				Start = @('#@debug@', '#@debug@');
				End = @('#@end-debug@', '#@end-debug@');
				PrefixBetween = '#';
			},
			@{
				Start = @('#@do-not-package@', '');
				End = @('#@end-do-not-package@', '');
				RemoveBetween = $true;
			},
			@{
				Start = @('#@alpha@', '#@alpha@');
				End = @('#@end-alpha@', '#@end-alpha@');
				PrefixBetween = '#';
				Types = @('alpha');
			}
		);
		'.xml' = @(
			@{
				Start = @('<!--@debug@-->', '<!--@debug@');
				End = @('<!--@end-debug@-->', '@end-debug@-->');
			},
			@{
				Start = @('<!--@non-debug@', '<!--@non-debug@-->');
				End = @('@end-non-debug@-->', '<!--@end-non-debug@-->');
			},
			@{
				Start = @('<!--@do-not-package@-->', '');
				End = @('<!--@end-do-not-package@-->', '');
				RemoveBetween = $true;
			},
			@{
				Start = @('<!--@alpha@-->', '<!--@alpha');
				End = @('<!--@end-alpha@-->', '@end-alpha@-->');
				Types = @('alpha');
			},
			@{
				Start = @('<!--@non-alpha@', '<!--@non-alpha@-->');
				End = @('@end-non-alpha@-->', '<!--@end-non-alpha@-->');
				Types = @('alpha');
			}
		);
	}
}
