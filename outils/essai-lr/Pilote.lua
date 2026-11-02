--[[ Pilote.lua : Lightroom piloté par fichiers, pour essayer SpektraLR dans le vrai Lightroom sans cliquer.

Toutes les secondes, le module regarde <son dossier>/pilote/commande.json. Il l'efface, l'exécute et écrit reponse.json
(`pilote.py` envoie la commande et attend la réponse). Interne : jamais publié, installé par `installer.sh`.

Sources : le SDK Lightroom Classic d'Adobe (LrCatalog, LrPhoto, LrExportSession, LrDevelopPreset) ; l'idée d'un
module qui interroge en boucle un point d'entrée local vient de lightroom-py (github.com/drshy-org/lightroom-py, MIT,
qui passe par un serveur HTTP Python). Ici, un simple dossier : rien à installer à côté de Lightroom.

Actions : ping, chercher (photos par nom de fichier), presets (dossiers et noms), copie (copie virtuelle d'une photo,
rangée dans une collection), rendre (presets ou réglages sur une copie, lecture des réglages, export), tirer (le
tirage du module, Tirage.lua, sur une copie).
]]
local LrApplication = import 'LrApplication'
local LrDate = import 'LrDate'
local LrExportSession = import 'LrExportSession'
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'

local Json = require 'Json'

-- dans le dossier du module, que Lightroom peut toujours lire et écrire
local DOSSIER = LrPathUtils.child(_PLUGIN.path, 'pilote')
local TITRE = 'SpektraLR (essai)'

local Pilote = { arret = false }
local copies = {}  -- clé donnée par `copie` → LrPhoto, le temps que Lightroom reste ouvert

local function journal(ligne)
  local f = io.open(LrPathUtils.child(DOSSIER, 'journal.txt'), 'a')
  if f then f:write(LrDate.timeToUserFormat(LrDate.currentTime(), '%H:%M:%S '), ligne, '\n') f:close() end
end

local function ecrire(nom, texte)
  local tmp = LrPathUtils.child(DOSSIER, nom .. '.tmp')
  local f = assert(io.open(tmp, 'w'))
  f:write(texte)
  f:close()
  local final = LrPathUtils.child(DOSSIER, nom)
  if LrFileUtils.exists(final) then LrFileUtils.delete(final) end
  assert(LrFileUtils.move(tmp, final))
end

local function catalogue() return LrApplication.activeCatalog() end

local function ecrireAuCatalogue(f)
  catalogue():withWriteAccessDo(TITRE, f, { timeout = 30 })
end

local function photo(cle)
  return copies[cle] or error('copie inconnue : ' .. tostring(cle))
end

local function trouverPreset(dossier, nom)
  for _, d in ipairs(LrApplication.developPresetFolders()) do
    if d:getName() == dossier then
      for _, p in ipairs(d:getDevelopPresets()) do
        if p:getName() == nom then return p end
      end
    end
  end
  error('preset introuvable : ' .. dossier .. ' ▸ ' .. nom)
end

-- Les réglages qui disent ce que Lightroom a fait du profil, sans la table elle-même.
local function lire(p, cles)
  local d = p:getDevelopSettings()
  local lu = {}
  for _, cle in ipairs(cles or { 'CameraProfile', 'ProcessVersion', 'Exposure2012', 'GrainAmount', 'HasCrop',
    'ConvertToGrayscale', 'WhiteBalance' }) do
    if type(d[cle]) ~= 'table' then lu[cle] = d[cle] end
  end
  if type(d.Look) == 'table' then
    local champs = {}
    for k in pairs(d.Look) do champs[#champs + 1] = k end
    table.sort(champs)
    lu.Look = { Name = d.Look.Name, Amount = d.Look.Amount, UUID = d.Look.UUID, champs = champs }
  end
  return lu
end

local function exporter(p, reglage, dossier, nom)
  local tmp = LrPathUtils.child(dossier, '.export')
  LrFileUtils.createAllDirectories(tmp)
  local s = {
    LR_export_destinationType = 'specificFolder', LR_export_destinationPathPrefix = tmp,
    LR_export_useSubfolder = false, LR_collisionHandling = 'overwrite', LR_reimportExportedPhoto = false,
    LR_renamingTokensOn = false, LR_extensionCase = 'lowercase', LR_useWatermark = false,
    LR_outputSharpeningOn = false, LR_embeddedMetadataOption = 'copyrightOnly', LR_removeLocationMetadata = true,
    LR_size_doConstrain = reglage.taille ~= nil, LR_size_resizeType = 'wh', LR_size_units = 'pixels',
    LR_size_maxWidth = reglage.taille, LR_size_maxHeight = reglage.taille, LR_size_doNotEnlarge = true,
    LR_size_resolution = 300, LR_size_resolutionUnits = 'inch',
  }
  if reglage.format == 'TIFF' then
    s.LR_format, s.LR_export_bitDepth, s.LR_export_colorSpace = 'TIFF', 16, 'ProPhotoRGB'
    s.LR_tiff_compressionMethod = 'compressionMethod_None'
  else
    s.LR_format, s.LR_jpeg_quality, s.LR_export_colorSpace, s.LR_export_bitDepth = 'JPEG', reglage.qualite or 0.9, 'sRGB', 8
  end
  local session = LrExportSession { photosToExport = { p }, exportSettings = s }
  session:doExportOnCurrentTask()
  for _, rendu in session:renditions() do
    local fait, chemin = rendu:waitForRender()
    if not fait then error('export : ' .. tostring(chemin)) end
    local final = LrPathUtils.child(dossier, nom .. '.' .. LrPathUtils.extension(chemin))
    if LrFileUtils.exists(final) then LrFileUtils.delete(final) end
    assert(LrFileUtils.move(chemin, final))
    return final
  end
  error('export : aucun rendu')
end

local actions = {}

function actions.ping()
  return { ok = true, lightroom = LrApplication.versionString(), catalogue = catalogue():getPath() }
end

function actions.chercher(cmd)
  local trouve = {}
  for _, nom in ipairs(cmd.noms) do
    local base = nom:gsub('%.[^.]*$', '')
    local liste = {}
    for _, p in ipairs(catalogue():findPhotos { searchDesc = { criteria = 'filename', operation = 'all', value = base } }) do
      if p:getFormattedMetadata('fileName') == nom then
        local lu = lire(p)
        lu.chemin, lu.virtuelle = p:getRawMetadata('path'), p:getRawMetadata('isVirtualCopy')
        lu.prise, lu.octets = p:getFormattedMetadata('dateTimeOriginal'), p:getRawMetadata('fileSize')
        liste[#liste + 1] = lu
      end
    end
    trouve[nom] = liste
  end
  return { ok = true, photos = trouve }
end

function actions.presets(cmd)
  local dossiers = {}
  for _, d in ipairs(LrApplication.developPresetFolders()) do
    if not cmd.dossier or d:getName() == cmd.dossier then
      local noms = {}
      for _, p in ipairs(d:getDevelopPresets()) do noms[#noms + 1] = p:getName() end
      dossiers[d:getName()] = noms
    end
  end
  return { ok = true, dossiers = dossiers }
end

local function id(p) return p and p.localIdentifier end

-- Décrit une photo : fichier, copie virtuelle ou non, photo maîtresse.
local function fiche(p)
  local maitre = p:getRawMetadata('masterPhoto')
  return { id = id(p), chemin = p:getRawMetadata('path'), virtuelle = p:getRawMetadata('isVirtualCopy'),
    copie = p:getFormattedMetadata('copyName'), maitre = maitre and id(maitre), rejet = p:getRawMetadata('pickStatus') == -1 }
end

-- Sélectionne `photo` et attend que Lightroom en fasse la cible (la sélection est asynchrone : son importeur Aperture
-- fait de même, en vérifiant et en réessayant).
local function cibler(cat, photo)
  for _ = 1, 3 do
    cat:setSelectedPhotos(photo, {})
    for _ = 1, 20 do
      LrTasks.sleep(0.25)
      if id(cat:getTargetPhoto()) == id(photo) and #cat:getTargetPhotos() == 1 then return true end
    end
  end
  return false
end

-- Copie virtuelle de la photo `chemin` : on l'affiche seule dans une collection temporaire (dans son dossier, une pile
-- repliée ou un filtre peuvent la cacher), on vérifie qu'elle est la seule cible, Lightroom crée la copie, on vérifie
-- que la copie vient bien d'elle, puis la vue de départ est remise et la collection temporaire supprimée.
function actions.copie(cmd)
  local cat = catalogue()
  local maitre = cat:findPhotoByPath(cmd.chemin) or error('pas au catalogue : ' .. cmd.chemin)
  local sources, cible, selection = cat:getActiveSources(), cat:getTargetPhoto(), cat:getTargetPhotos()
  local temporaire
  ecrireAuCatalogue(function()
    temporaire = cat:createCollection('SpektraLR (essai) - source', nil, true)
    temporaire:addPhotos { maitre }
  end)
  cat:setActiveSources { temporaire }
  local copie, erreur
  if not cibler(cat, maitre) then
    erreur = 'Lightroom ne cible pas la photo voulue : aucune copie créée'
  else
    local nouvelles
    local fait, e = LrTasks.pcall(function() nouvelles = cat:createVirtualCopies(cmd.nom) end)
    LrTasks.sleep(0.5)
    copie = type(nouvelles) == 'table' and nouvelles[1] or cat:getTargetPhoto()
    if not fait then erreur = tostring(e) copie = nil end
  end
  cat:setActiveSources(sources)
  if cible then cat:setSelectedPhotos(cible, selection) end
  LrTasks.sleep(0.5)
  ecrireAuCatalogue(function() temporaire:delete() end)
  if erreur then return { ok = false, erreur = erreur } end
  local f = fiche(copie)
  if not f.virtuelle or f.maitre ~= id(maitre) then
    return { ok = false, erreur = 'la copie ne vient pas de la photo voulue', copie = f }
  end
  if cmd.collection then
    ecrireAuCatalogue(function() cat:createCollection(cmd.collection, nil, true):addPhotos { copie } end)
  end
  copies[cmd.cle] = copie
  return { ok = true, copie = f, reglages = lire(copie) }
end

local function collection(nom)
  for _, c in ipairs(catalogue():getChildCollections()) do
    if c:getName() == nom then return c end
  end
end

-- Les photos d'une collection, décrites.
function actions.inventaire(cmd)
  local c = collection(cmd.collection) or error('collection introuvable : ' .. cmd.collection)
  local liste = {}
  for _, p in ipairs(c:getPhotos()) do
    local f = fiche(p)
    local m = p:getRawMetadata('masterPhoto')
    f.cheminMaitre = m and m:getRawMetadata('path')
    liste[#liste + 1] = f
  end
  return { ok = true, photos = liste }
end

-- Reprend une copie déjà au catalogue (après un redémarrage de Lightroom) sous une clé.
function actions.adopter(cmd)
  -- `id` est pris par l'identifiant de la commande : le numéro de la photo vient dans `photo`
  copies[cmd.cle] = catalogue():getPhotoByLocalId(cmd.photo) or error('photo introuvable : ' .. tostring(cmd.photo))
  return { ok = true, copie = fiche(copies[cmd.cle]) }
end

-- Copies faites par erreur : rejetées, renommées et rangées à part, pour les supprimer d'un coup à la main
-- (le SDK ne sait pas retirer une photo du catalogue).
function actions.ecarter(cmd)
  local cat = catalogue()
  local faites = {}
  ecrireAuCatalogue(function()
    local aSupprimer = cat:createCollection(cmd.versCollection, nil, true)
    local depart = cmd.depuisCollection and collection(cmd.depuisCollection)
    for _, n in ipairs(cmd.ids) do
      local p = cat:getPhotoByLocalId(n) or error('photo introuvable : ' .. tostring(n))
      if not p:getRawMetadata('isVirtualCopy') then error('pas une copie virtuelle, on n\'y touche pas : ' .. tostring(n)) end
      p:setRawMetadata('pickStatus', -1)
      pcall(function() p:setRawMetadata('copyName', cmd.nom) end)
      aSupprimer:addPhotos { p }
      if depart then depart:removePhotos { p } end
      faites[#faites + 1] = fiche(p)
    end
  end)
  return { ok = true, photos = faites }
end

-- Pour le diagnostic : un bout de Lua, si Lightroom laisse loadstring.
function actions.lua(cmd)
  -- pas de setfenv dans Lightroom : le code lit le catalogue et les copies par require('Pilote')
  local f = assert(loadstring(cmd.code))
  Pilote.catalogue, Pilote.copies = catalogue(), copies
  return { ok = true, resultat = f() }
end

function actions.rendre(cmd)
  local p = photo(cmd.cle)
  for _, etape in ipairs(cmd.etapes or {}) do
    if etape.preset then
      local preset = trouverPreset(etape.dossier or 'SpektraLR', etape.preset)
      ecrireAuCatalogue(function() p:applyDevelopPreset(preset, _PLUGIN) end)
    elseif etape.reglages then
      ecrireAuCatalogue(function() p:applyDevelopSettings(etape.reglages, TITRE) end)
    end
  end
  local reponse = { ok = true, reglages = lire(p, cmd.lire) }
  if cmd.export then reponse.fichier = exporter(p, cmd.export, cmd.dossier, cmd.nom) end
  return reponse
end

function actions.tirer(cmd)
  local fichier, erreur = require('Tirage').tirer(catalogue(), photo(cmd.cle), cmd.choix)
  return { ok = fichier ~= nil, fichier = fichier, erreur = erreur }
end

local function executer(cmd)
  local action = actions[cmd.action] or error('action inconnue : ' .. tostring(cmd.action))
  return action(cmd)
end

function Pilote.tour()
  local entree = LrPathUtils.child(DOSSIER, 'commande.json')
  if not LrFileUtils.exists(entree) then return end
  local texte = LrFileUtils.readFile(entree)
  LrFileUtils.delete(entree)
  local lu, cmd = pcall(Json.decode, texte)
  local reponse
  if not lu or type(cmd) ~= 'table' then
    reponse = { ok = false, erreur = 'commande illisible : ' .. tostring(cmd) }
  else
    journal('← ' .. tostring(cmd.action) .. ' ' .. tostring(cmd.id))
    local fait, resultat = LrTasks.pcall(executer, cmd)
    reponse = fait and resultat or { ok = false, erreur = tostring(resultat) }
    reponse.id = cmd.id
  end
  journal('→ ' .. tostring(reponse.ok) .. ' ' .. tostring(reponse.erreur or ''))
  ecrire('reponse.json', Json.encode(reponse))
end

function Pilote.demarrer()
  if Pilote.demarre then return end
  Pilote.demarre = true
  LrFileUtils.createAllDirectories(DOSSIER)
  LrTasks.startAsyncTask(function()
    journal('démarrage, Lightroom ' .. LrApplication.versionString())
    while not Pilote.arret do
      if LrFileUtils.exists(DOSSIER) then
        local fait, erreur = LrTasks.pcall(Pilote.tour)
        if not fait then journal('erreur : ' .. tostring(erreur)) end
      end
      LrTasks.sleep(1)
    end
  end)
end

return Pilote
