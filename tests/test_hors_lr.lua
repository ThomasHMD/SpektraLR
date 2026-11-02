-- Contrôles hors de Lightroom : Json et Reglages (sans SDK). Lancer : lua tests/test_hors_lr.lua
package.path = arg[0]:gsub('[^/]*$', '') .. '../SpektraLR.lrplugin/?.lua;' .. package.path

local Json = require 'Json'
local Reglages = require 'Reglages'

local n = 0
local function verifie(condition, message)
  n = n + 1
  if not condition then error('ÉCHEC : ' .. message, 2) end
end

-- Json : une réponse de la CLI, imprimée « pretty » comme le fait SpektraLab
local r = Json.decode([[
{
  "files" : [
    "\/Photos\/Été 2026\/DSC_0001.tif"
  ],
  "n" : -1.5e2,
  "nul" : null,
  "ok" : true,
  "u" : "é😀"
}
]])
verifie(r.ok == true, 'booléen')
verifie(r.files[1] == '/Photos/Été 2026/DSC_0001.tif', 'chaîne UTF-8 et \\/')
verifie(r.n == -150, 'nombre en notation exponentielle')
verifie(r.u == 'é😀', 'échappements \\u et paire de substitution')
verifie(r.nul == Json.null, 'null')
verifie(#Json.decode('[]') == 0 and next(Json.decode('{}')) == nil, 'conteneurs vides')
verifie(not pcall(Json.decode, '{"a":1,}'), 'virgule finale refusée')
verifie(not pcall(Json.decode, '{"a":1} x'), 'texte après la valeur refusé')
verifie(not pcall(Json.decode, ''), 'texte vide refusé')

local e = Json.encode { params = { filmStock = 'kodak_portra_400', halationActive = true, effects = { halation = 1.25 } } }
verifie(e == '{"params":{"effects":{"halation":1.25},"filmStock":"kodak_portra_400","halationActive":true}}',
  'encodage trié : ' .. e)
verifie(Json.decode(Json.encode { s = 'a"b\\c\n\1' }).s == 'a"b\\c\n\1', 'aller-retour des échappements')
verifie(Json.encode { 1, 2, 3 } == '[1,2,3]', 'tableau')

-- Reglages
local base = { film = 'kodak_portra_400', papier = 'kodak_endura', format = '135', halo = true, haloForce = 1.5,
  grain = false, grainForce = 2, balanceTelleQuelle = 'asShot' }

local p = Reglages.patch(base, nil)
verifie(p.params.filmStock == 'kodak_portra_400' and p.params.printStock == 'kodak_endura', 'film et papier')
verifie(p.params.halationActive == true and p.params.effects.halation == 1.5, 'halo actif et sa force')
verifie(p.params.grainActive == false and p.params.effects.grain == nil, 'grain coupé : pas de force envoyée')
verifie(p.decode == nil and p.params.exposureCompensationEV == nil, 'sans réglages Lightroom : rien de plus')

local sansEffet = Reglages.patch({ film = 'x', halo = false, grain = false }, nil)
verifie(sansEffet.params.effects == nil, 'pas d\'objet effects vide (il s\'encoderait en [])')

local diapo = Reglages.patch({ film = 'fuji_provia', papier = 'kodak_endura', diapo = true }, nil)
verifie(diapo.params.printStock == nil, 'diapositive : pas de papier')

local lr = { reprendreLR = true }
for k, v in pairs(base) do lr[k] = v end
p = Reglages.patch(lr, { Exposure2012 = 0.7, WhiteBalance = 'Custom', Temperature = 4300, Tint = 12 })
verifie(p.params.exposureCompensationEV == 0.7, 'exposition reprise')
verifie(p.decode.temperature == 4300 and p.decode.tint == 12 and p.decode.whiteBalance == nil, 'balance reprise')

p = Reglages.patch(lr, { Exposure2012 = 5, WhiteBalance = 'Custom', Temperature = 50000, Tint = -200 })
verifie(p.params.exposureCompensationEV == 4 and p.decode.temperature == 12000 and p.decode.tint == -150, 'bornes')

p = Reglages.patch(lr, { Exposure2012 = 0, WhiteBalance = 'As Shot', Temperature = 5200, Tint = 3 })
verifie(p.decode.whiteBalance == 'asShot' and p.decode.temperature == nil, 'balance telle quelle')

verifie(Reglages.estDiapo { type = 'positive' } and not Reglages.estDiapo { type = 'negative' }, 'détection diapositive')

print(n .. ' contrôles OK')
