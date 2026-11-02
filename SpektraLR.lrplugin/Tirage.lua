--[[ Tirage.lua : le tirage d'une photo, sans fenêtre (Tirer.lua pour la fenêtre et la boucle). ]]
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'

local Reglages = require 'Reglages'
local Spektra = require 'Spektra'

local Tirage = { TITRE = 'SpektraLR' }

-- Une photo : reset, edit, export, puis import empilé. Renvoie le fichier écrit, ou nil et l'erreur.
function Tirage.tirer(catalogue, photo, choix)
  local chemin = photo:getRawMetadata('path')
  if choix.repartirDeZero then
    local fait, erreur = Spektra.appeler { 'reset', chemin }
    if not fait then return nil, erreur end
  end
  local dev = choix.reprendreLR and photo:getDevelopSettings() or nil
  local fait, erreur = Spektra.modifier(chemin, Reglages.patch(choix, dev))
  if not fait then return nil, erreur end
  local fichiers, erreurExport = Spektra.exporter(chemin, choix.recette, LrPathUtils.parent(chemin))
  if not fichiers then return nil, erreurExport end
  local fichier = fichiers[1]
  if not catalogue:findPhotoByPath(fichier) then
    local importe, erreurImport = LrTasks.pcall(function()
      catalogue:withWriteAccessDo(Tirage.TITRE, function() catalogue:addPhoto(fichier, photo, 'above') end)
    end)
    if not importe then return nil, 'Écrit mais pas importé (' .. fichier .. ') : ' .. tostring(erreurImport) end
  end
  return fichier
end

return Tirage
