
@{
	ApiRoot = 'https://wow.curseforge.com/api/';
	TokenFile = 'curseforge.token';
	Excludes = @('.*');
	LibStore = 'D:\DEV\Lua\!Libs';
	ReplaceMask = @('*.lua', '*.toc', '*.xml');
	Replace = @{
		'.lua' = @{
			'*' = @{
				'--@debug@' = '--[===[@debug';
				'--@end-debug@' = '--@end-debug]===]';
				'--[===[@non-debug@' = '--@non-debug@';
				'--@end-non-debug@]===]' = '--@end-non-debug@'
			};
			'alpha' = @{}
		};
		'.toc' = @{ };
		'.xml' = @{
			'*' = @{
				'<!--@debug@-->' = '<!--@debug';
				'<!--@end-debug@-->' = '@end-debug@-->'
			};
			'alpha' = @{}
		}
	}
}
