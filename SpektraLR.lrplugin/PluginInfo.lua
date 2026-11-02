--[[ PluginInfo.lua : réglage du module dans Fichier ▸ Gestionnaire de modules externes. ]]
local LrPrefs = import 'LrPrefs'
local LrView = import 'LrView'

local Spektra = require 'Spektra'

return {
  sectionsForTopOfDialog = function(f)
    local prefs = LrPrefs.prefsForPlugin()
    return {
      {
        title = 'SpektraLab',
        f:row {
          f:static_text { title = 'Commande :' },
          f:edit_field { value = LrView.bind { key = 'commande', bind_to_object = prefs }, width_in_chars = 50 },
        },
        f:static_text {
          title = 'Vide = ' .. Spektra.commandeParDefaut()
            .. ', posée par SpektraLab ▸ Réglages ▸ Agents ▸ Installer (l\'accès doit y être activé).',
          width_in_chars = 70, height_in_lines = 2,
        },
      },
    }
  end,
}
