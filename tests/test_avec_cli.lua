--[[ Essai de bout en bout hors de Lightroom : Tirer.lua tourne sur un SDK simulé, avec la vraie commande
`spektralab`, sur la COPIE d'un RAW (le tirage s'écrit à côté d'elle).

  lua tests/test_avec_cli.lua <copie d'un RAW> [film]

La fenêtre est validée telle quelle (choix par défaut, film forcé si donné) ; l'import au catalogue est relevé.
]]
local dossierTests = arg[0]:gsub('[^/]*$', '')
package.path = dossierTests .. '../SpektraLR.lrplugin/?.lua;' .. package.path

local brut, filmVoulu = arg[1], arg[2]
assert(brut and io.open(brut), 'usage : lua tests/test_avec_cli.lua <copie d\'un RAW> [film]')

local function parent(p) return (p:gsub('/[^/]*$', '')) end
local releve = { ajouts = {}, messages = {} }

local SDK = {
  LrTasks = {
    -- Comme Lightroom sur Mac : le statut de wait(), soit le code de sortie × 256.
    execute = function(cmd)
      local _, _, code = os.execute(cmd)
      return (code or 0) * 256
    end,
    pcall = pcall,
  },
  LrFileUtils = {
    exists = function(p) local f = io.open(p) if f then f:close() return true end return false end,
    readFile = function(p) local f = assert(io.open(p)) local t = f:read('*a') f:close() return t end,
    delete = function(p) os.remove(p) end,
  },
  LrPathUtils = {
    child = function(d, n) return d .. '/' .. n end,
    parent = parent,
    getStandardFilePath = function(quoi) return quoi == 'home' and os.getenv('HOME') or parent(brut) end,
  },
  LrPrefs = { prefsForPlugin = (function() local prefs = {} return function() return prefs end end)() },
  LrBinding = { makePropertyTable = function() return {} end },
  LrView = {
    osFactory = function()
      return setmetatable({}, { __index = function() return function(_, args) return args or {} end end })
    end,
    bind = function(k) return { bind = k } end,
    share = function(k) return k end,
  },
  LrDialogs = {
    presentModalDialog = function(t)
      local p = t.contents.bind_to_object
      if filmVoulu then p.film = filmVoulu end
      releve.choix = { film = p.film, papier = p.papier, format = p.format, recette = p.recette }
      return 'ok'
    end,
    message = function(m, info) releve.messages[#releve.messages + 1] = m .. ' / ' .. tostring(info) end,
    showBezel = function(m) releve.messages[#releve.messages + 1] = m end,
    attachErrorDialogToFunctionContext = function() end,
  },
  LrFunctionContext = { postAsyncTaskWithContext = function(_, f) f({}) end },
  LrProgressScope = function()
    return { isCanceled = function() return false end, setCaption = function() end,
      setPortionComplete = function() end, done = function() end }
  end,
  LrApplication = {
    activeCatalog = function()
      local photo = {
        getRawMetadata = function(_, cle) return ({ path = brut, fileFormat = 'RAW' })[cle] end,
        getFormattedMetadata = function() return brut:match('[^/]*$') end,
        getDevelopSettings = function() return { Exposure2012 = 0.3, WhiteBalance = 'As Shot', Temperature = 5100, Tint = 2 } end,
      }
      return {
        getTargetPhotos = function() return { photo } end,
        findPhotoByPath = function() return nil end,
        withWriteAccessDo = function(_, _, f) f() end,
        addPhoto = function(_, chemin, pile, position) releve.ajouts[#releve.ajouts + 1] = { chemin, pile == photo, position } end,
      }
    end,
  },
}
function import(nom) return assert(SDK[nom], 'SDK simulé : ' .. nom .. ' manque') end

dofile(dossierTests .. '../SpektraLR.lrplugin/Tirer.lua')

print('choix : ' .. releve.choix.film .. ' / papier « ' .. tostring(releve.choix.papier) .. ' » / '
  .. tostring(releve.choix.format) .. ' / ' .. releve.choix.recette)
for _, m in ipairs(releve.messages) do print('message : ' .. m) end
local a = releve.ajouts[1]
assert(a, 'aucun import au catalogue')
assert(io.open(a[1]), 'le fichier importé n\'existe pas : ' .. a[1])
assert(a[2] and a[3] == 'above', 'pas empilé au-dessus de l\'original')
print('importé et empilé : ' .. a[1])
