--[[ Reglages.lua : le patch JSON envoyé à `spektralab edit`, d'après les choix de la fenêtre et les réglages
Lightroom de la photo.

Sans appel au SDK, pour être testé hors de Lightroom (tests/test_hors_lr.lua). Les chemins des champs viennent
du schéma de SpektraLab (`spektralab schema`, AgentSchema.swift) :
  params.filmStock, params.printStock, params.filmFrame, params.halationActive, params.grainActive,
  params.effects.halation et params.effects.grain (× la force propre au film), params.exposureCompensationEV
  (-4 à +4 IL, ajoutés à la mesure), decode.whiteBalance, decode.temperature (2000 à 12000 K),
  decode.tint (-150 à +150, la même échelle que Lightroom).
]]
local Reglages = {}

local function borne(v, min, max)
  return math.max(min, math.min(max, v))
end

-- Un film inversible (diapositive) est scanné, pas tiré : SpektraLab refuse alors un papier (`printStock`).
-- `spektralab stocks` le marque "type": "positive" (Provia, Velvia, Ektachrome, Kodachrome).
function Reglages.estDiapo(stock)
  return stock.type == 'positive'
end

--[[ choix :
  film, papier (nil = aucun), format (nil = celui de SpektraLab), diapo,
  halo, haloForce, grain, grainForce,
  reprendreLR, balanceTelleQuelle (la valeur « As Shot » de decode.whiteBalance, lue dans le schéma)
dev : photo:getDevelopSettings(), ou nil ]]
function Reglages.patch(choix, dev)
  local params = {
    filmStock = choix.film,
    halationActive = choix.halo == true,
    grainActive = choix.grain == true,
  }
  local effets = {}
  if choix.halo and tonumber(choix.haloForce) then effets.halation = tonumber(choix.haloForce) end
  if choix.grain and tonumber(choix.grainForce) then effets.grain = tonumber(choix.grainForce) end
  if next(effets) then params.effects = effets end
  if choix.format and choix.format ~= '' then params.filmFrame = choix.format end
  if not choix.diapo and choix.papier and choix.papier ~= '' then params.printStock = choix.papier end

  local patch = { params = params }
  if choix.reprendreLR and dev then
    -- L'exposition de Lightroom devient celle du film à la prise de vue (le tirage suit, comme au labo).
    params.exposureCompensationEV = borne(tonumber(dev.Exposure2012) or 0, -4, 4)
    if dev.WhiteBalance == 'As Shot' or not tonumber(dev.Temperature) then
      if choix.balanceTelleQuelle then patch.decode = { whiteBalance = choix.balanceTelleQuelle } end
    else
      patch.decode = {
        temperature = borne(tonumber(dev.Temperature), 2000, 12000),
        tint = borne(tonumber(dev.Tint) or 0, -150, 150),
      }
    end
  end
  return patch
end

return Reglages
