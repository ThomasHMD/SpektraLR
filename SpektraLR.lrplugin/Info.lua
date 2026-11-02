return {
  LrSdkVersion = 13.0,
  LrSdkMinimumVersion = 10.0,
  LrToolkitIdentifier = 'com.thomashammoudi.spektralr',
  LrPluginName = 'SpektraLR',
  LrPluginInfoProvider = 'PluginInfo.lua',
  LrLibraryMenuItems = {
    { title = 'SpektraLR…', file = 'Tirer.lua', enabledWhen = 'photosSelected' },
  },
  LrExportMenuItems = {
    { title = 'SpektraLR…', file = 'Tirer.lua', enabledWhen = 'photosSelected' },
  },
  VERSION = { major = 0, minor = 1, revision = 1 },
}
