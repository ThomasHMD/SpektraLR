-- Module d'essai de SpektraLR (interne, jamais publié) : voir Pilote.lua.
return {
  LrSdkVersion = 13.0,
  LrSdkMinimumVersion = 10.0,
  LrToolkitIdentifier = 'com.thomashammoudi.spektralr.essai',
  LrPluginName = 'SpektraLR (essai)',
  LrInitPlugin = 'Init.lua',
  -- lightroom://com.thomashammoudi.spektralr.essai/… démarre le pilote sans clic (comme le module Flickr d'Adobe)
  URLHandler = 'URLHandler.lua',
  -- Lightroom ne lit LrForceInitPlugin qu'en construisant les menus (AgSdkMenus.lua) : il faut une entrée de menu.
  LrForceInitPlugin = true,
  LrLibraryMenuItems = { { title = 'SpektraLR (essai) : pilote', file = 'Etat.lua' } },
  LrShutdownPlugin = 'Arret.lua',
  VERSION = { major = 0, minor = 1, revision = 0 },
}
