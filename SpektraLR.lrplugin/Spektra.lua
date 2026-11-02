--[[ Spektra.lua : appelle la commande `spektralab` (la CLI de SpektraLab) et lit sa réponse.

Chaque commande écrit un objet JSON sur sa sortie standard, avec "ok" ; code de sortie 0 = fait, 1 = échec,
2 = refusé (accès coupé dans SpektraLab ▸ Réglages ▸ Agents, fichier qu'il n'ouvre pas, valeur hors plage).
Source : AgentCLI.swift du dépôt JamesQiu2005/SpektraLab.
]]
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrPrefs = import 'LrPrefs'
local LrTasks = import 'LrTasks'

local Json = require 'Json'

local Spektra = {}

-- Là où SpektraLab ▸ Réglages ▸ Agents ▸ Installer pose la commande (un script de deux lignes vers l'appli).
function Spektra.commandeParDefaut()
  return LrPathUtils.child(LrPathUtils.getStandardFilePath('home'), '.local/bin/spektralab')
end

function Spektra.commande()
  local p = LrPrefs.prefsForPlugin().commande
  if p and p ~= '' then return p end
  return Spektra.commandeParDefaut()
end

local function guillemets(s)
  return "'" .. (tostring(s):gsub("'", "'\\''")) .. "'"
end

local compteur = 0
local function fichierTemporaire(suffixe)
  compteur = compteur + 1
  return LrPathUtils.child(LrPathUtils.getStandardFilePath('temp'),
    string.format('spektralr-%d-%d%s', os.time(), compteur, suffixe))
end

local function lireEtEffacer(chemin)
  if not LrFileUtils.exists(chemin) then return '' end
  local texte = LrFileUtils.readFile(chemin) or ''
  LrFileUtils.delete(chemin)
  return texte
end

-- Lance `spektralab <args…>`. Renvoie la réponse décodée, ou nil et un message d'erreur.
function Spektra.appeler(args)
  local commande = Spektra.commande()
  if not LrFileUtils.exists(commande) then
    return nil, 'Commande SpektraLab introuvable : ' .. commande
      .. '\nDans SpektraLab ▸ Réglages ▸ Agents : activer l\'accès, puis « Installer ».'
  end
  local sortie, journal = fichierTemporaire('.json'), fichierTemporaire('.log')
  local morceaux = { guillemets(commande) }
  for _, a in ipairs(args) do morceaux[#morceaux + 1] = guillemets(a) end
  local code = LrTasks.execute(table.concat(morceaux, ' ') .. ' >' .. guillemets(sortie) .. ' 2>' .. guillemets(journal))
  -- Sur Mac, LrTasks.execute rend le statut de wait() : le code de sortie × 256.
  if code and code > 255 then code = math.floor(code / 256) end
  local texte, erreurs = lireEtEffacer(sortie), lireEtEffacer(journal)

  local lu, reponse = pcall(Json.decode, texte)
  if not lu or type(reponse) ~= 'table' then
    return nil, string.format('Réponse illisible de SpektraLab (code %s).\n%s', tostring(code), erreurs:sub(-600))
  end
  if code ~= 0 or reponse.ok ~= true then
    return nil, tostring(reponse.error or ('SpektraLab a échoué (code ' .. tostring(code) .. ').')), reponse
  end
  return reponse
end

function Spektra.modifier(fichier, patch)
  local chemin = fichierTemporaire('.json')
  local f = assert(io.open(chemin, 'w'))
  f:write(Json.encode(patch))
  f:close()
  local reponse, erreur = Spektra.appeler { 'edit', fichier, '--patch', '@' .. chemin }
  LrFileUtils.delete(chemin)
  return reponse, erreur
end

-- Exporte avec une recette de SpektraLab dans `dossier` ; renvoie la liste des fichiers écrits.
function Spektra.exporter(fichier, recette, dossier)
  local args = { 'export', fichier }
  if recette and recette ~= '' then
    args[#args + 1] = '--recipe'
    args[#args + 1] = recette
  end
  if dossier then
    args[#args + 1] = '--to'
    args[#args + 1] = dossier
  end
  local reponse, erreur = Spektra.appeler(args)
  if not reponse then return nil, erreur end
  if type(reponse.files) ~= 'table' or not reponse.files[1] then
    return nil, 'SpektraLab n\'a écrit aucun fichier.'
  end
  return reponse.files
end

return Spektra
