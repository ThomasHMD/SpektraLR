--[[ Tirer.lua : Bibliothèque (ou Fichier) ▸ Modules externes ▸ SpektraLR…

Pour chaque RAW choisi, SpektraLab développe le négatif et le tire sur papier (CLI `spektralab` : reset, edit,
export). Le fichier sort à côté de l'original et rentre au catalogue, empilé au-dessus de lui.
]]
local LrApplication = import 'LrApplication'
local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrPrefs = import 'LrPrefs'
local LrProgressScope = import 'LrProgressScope'
local LrView = import 'LrView'

local Reglages = require 'Reglages'
local Spektra = require 'Spektra'
local Tirage = require 'Tirage'

local TITRE = Tirage.TITRE
-- SpektraLab part du fichier brut du boîtier : un JPEG ou un TIFF n'a plus de négatif à développer.
local FORMATS_BRUTS = { RAW = true, DNG = true }

local function champ(schema, chemin)
  for _, f in ipairs(schema.fields or {}) do
    if f.path == chemin then return f end
  end
end

local function valeurDans(items, v)
  for _, item in ipairs(items) do
    if item.value == v then return v end
  end
end

local function valeurQuiContient(items, motif)
  for _, item in ipairs(items) do
    if string.find(string.lower(tostring(item.value)), motif, 1, true) then return item.value end
  end
end

-- Lit films, papiers, recettes et schéma ; ouvre la fenêtre. Renvoie les choix, ou nil si annulé ou impossible.
local function demanderChoix(context)
  local stocks, recettes, schema, erreur
  stocks, erreur = Spektra.appeler { 'stocks' }
  if stocks then recettes, erreur = Spektra.appeler { 'recipes' } end
  if recettes then schema, erreur = Spektra.appeler { 'schema' } end
  if not schema then
    LrDialogs.message('SpektraLab ne répond pas.', erreur, 'critical')
    return nil
  end
  if not recettes.recipes or not recettes.recipes[1] then
    LrDialogs.message('SpektraLab n\'a aucune recette d\'export.',
      'En créer une dans sa page Export : TIFF 16 bits, ProPhoto RGB, taille d\'origine.', 'critical')
    return nil
  end

  local filmsParId = {}
  local films, papiers, formats, listeRecettes = {}, { { title = 'Celui que conseille le film', value = '' } }, {}, {}
  for _, s in ipairs(stocks.films or {}) do
    filmsParId[s.id] = s
    films[#films + 1] = { title = s.name or s.id, value = s.id }
  end
  for _, s in ipairs(stocks.papers or {}) do papiers[#papiers + 1] = { title = s.name or s.id, value = s.id } end
  local fFormat = champ(schema, 'params.filmFrame')
  for _, id in ipairs(fFormat and fFormat.enum or {}) do formats[#formats + 1] = { title = id, value = id } end
  for _, r in ipairs(recettes.recipes) do
    listeRecettes[#listeRecettes + 1] = { title = r.name .. ' (' .. tostring(r.format or '?') .. ')', value = r.name }
  end
  local fHalo = champ(schema, 'params.effects.halation') or { min = 0, max = 3 }
  local fGrain = champ(schema, 'params.effects.grain') or { min = 0, max = 3 }
  local fBalance = champ(schema, 'decode.whiteBalance')
  local balanceTelleQuelle
  for _, v in ipairs(fBalance and fBalance.enum or {}) do
    if string.lower(v):gsub('[^a-z]', '') == 'asshot' then balanceTelleQuelle = v end
  end

  local prefs = LrPrefs.prefsForPlugin()
  local p = LrBinding.makePropertyTable(context)
  p.film = valeurDans(films, prefs.film) or (films[1] and films[1].value)
  p.papier = valeurDans(papiers, prefs.papier) or ''
  p.format = valeurDans(formats, prefs.format) or valeurQuiContient(formats, '135') or (formats[1] and formats[1].value)
  -- Par défaut une recette TIFF (SpektraLab livre « TIFF 16-bit — ProPhoto ») : Lightroom la retouche sans perte.
  p.recette = valeurDans(listeRecettes, prefs.recette) or valeurQuiContient(listeRecettes, 'lightroom')
    or valeurQuiContient(listeRecettes, 'tiff') or listeRecettes[1].value
  p.halo = prefs.halo ~= false
  p.haloForce = prefs.haloForce or 1
  p.grain = prefs.grain ~= false
  p.grainForce = prefs.grainForce or 1
  p.reprendreLR = prefs.reprendreLR ~= false
  p.repartirDeZero = prefs.repartirDeZero ~= false

  local f = LrView.osFactory()
  local function ligne(etiquette, controle)
    return f:row {
      f:static_text { title = etiquette, width = LrView.share 'etiquettes', alignment = 'right' },
      controle,
    }
  end
  local function effet(cle, bornes)
    return f:row {
      f:checkbox { title = '', value = LrView.bind(cle) },
      f:slider { min = bornes.min, max = bornes.max, integral = false, width = 220,
        value = LrView.bind(cle .. 'Force'), enabled = LrView.bind(cle) },
      f:edit_field { min = bornes.min, max = bornes.max, precision = 2, width_in_digits = 4,
        value = LrView.bind(cle .. 'Force'), enabled = LrView.bind(cle) },
    }
  end
  local lignes = {
    bind_to_object = p,
    spacing = f:control_spacing(),
    ligne('Film', f:popup_menu { items = films, value = LrView.bind 'film', width_in_chars = 32 }),
    ligne('Papier', f:popup_menu { items = papiers, value = LrView.bind 'papier', width_in_chars = 32 }),
  }
  if formats[1] then
    lignes[#lignes + 1] = ligne('Format du négatif', f:popup_menu { items = formats, value = LrView.bind 'format' })
  end
  lignes[#lignes + 1] = ligne('Halo', effet('halo', fHalo))
  lignes[#lignes + 1] = ligne('Grain', effet('grain', fGrain))
  lignes[#lignes + 1] = ligne('Recette d\'export', f:popup_menu { items = listeRecettes, value = LrView.bind 'recette' })
  lignes[#lignes + 1] = f:checkbox { value = LrView.bind 'reprendreLR',
    title = 'Reprendre l\'exposition et la balance des blancs de Lightroom' }
  lignes[#lignes + 1] = f:checkbox { value = LrView.bind 'repartirDeZero',
    title = 'Repartir des réglages par défaut (oublie les retouches faites dans SpektraLab)' }

  if LrDialogs.presentModalDialog { title = TITRE, contents = f:column(lignes), actionVerb = 'Tirer' } ~= 'ok' then
    return nil
  end

  for _, cle in ipairs { 'film', 'papier', 'format', 'recette', 'halo', 'haloForce', 'grain', 'grainForce',
    'reprendreLR', 'repartirDeZero' } do
    prefs[cle] = p[cle]
  end
  local stock = filmsParId[p.film] or {}
  local diapo = Reglages.estDiapo(stock)
  local papier = p.papier ~= '' and p.papier or stock.declaredPaper
  return {
    film = p.film, papier = papier, diapo = diapo, format = p.format, recette = p.recette,
    halo = p.halo, haloForce = p.haloForce, grain = p.grain, grainForce = p.grainForce,
    reprendreLR = p.reprendreLR, repartirDeZero = p.repartirDeZero, balanceTelleQuelle = balanceTelleQuelle,
  }
end

LrFunctionContext.postAsyncTaskWithContext(TITRE, function(context)
  LrDialogs.attachErrorDialogToFunctionContext(context)
  local catalogue = LrApplication.activeCatalog()
  local bruts, autres = {}, 0
  for _, photo in ipairs(catalogue:getTargetPhotos()) do
    if FORMATS_BRUTS[photo:getRawMetadata('fileFormat')] then bruts[#bruts + 1] = photo else autres = autres + 1 end
  end
  if not bruts[1] then
    LrDialogs.message('Aucun RAW dans la sélection.', 'SpektraLab part du fichier brut du boîtier (RAW ou DNG).', 'info')
    return
  end

  local choix = demanderChoix(context)
  if not choix then return end

  local progression = LrProgressScope { title = TITRE, functionContext = context }
  local faits, echecs = 0, {}
  for i, photo in ipairs(bruts) do
    if progression:isCanceled() then break end
    local nom = photo:getFormattedMetadata('fileName')
    progression:setCaption(string.format('%s (%d sur %d)', nom, i, #bruts))
    local fichier, erreur = Tirage.tirer(catalogue, photo, choix)
    if fichier then faits = faits + 1 else echecs[#echecs + 1] = nom .. ' : ' .. tostring(erreur) end
    progression:setPortionComplete(i, #bruts)
  end
  progression:done()

  local bilan = string.format('%d tirage(s) fait(s) sur %d RAW.', faits, #bruts)
  if autres > 0 then bilan = bilan .. string.format(' %d fichier(s) non RAW laissé(s) de côté.', autres) end
  if echecs[1] then
    LrDialogs.message(bilan, table.concat(echecs, '\n'), 'warning')
  else
    LrDialogs.showBezel(bilan)
  end
end)
