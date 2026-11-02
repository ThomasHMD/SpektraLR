--[[ Json.lua : décodeur et encodeur JSON minimal (le SDK de Lightroom n'en a pas).

Lua 5.1, celui de Lightroom. `Json.null` représente le null de JSON ; un objet s'encode avec ses clés triées.
Une table vide s'encode en tableau `[]` : ne pas en passer là où un objet est attendu.
]]
local Json = {}

Json.null = setmetatable({}, { __tostring = function() return 'null' end })

-- Encodage -------------------------------------------------------------------------------------------------------

local ECHAPPEMENTS = {
  ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
}

local function encoderChaine(s)
  return '"' .. (s:gsub('[%c"\\]', function(c)
    return ECHAPPEMENTS[c] or string.format('\\u%04x', c:byte())
  end)) .. '"'
end

local function estTableau(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= 'number' then return false end
    n = n + 1
  end
  return n == #t
end

function Json.encode(v)
  local t = type(v)
  if v == nil or v == Json.null then return 'null' end
  if t == 'boolean' then return tostring(v) end
  if t == 'number' then
    if v ~= v or v == math.huge or v == -math.huge then error('nombre non encodable : ' .. tostring(v)) end
    if math.floor(v) == v and math.abs(v) < 1e15 then return string.format('%d', v) end
    return string.format('%.10g', v)
  end
  if t == 'string' then return encoderChaine(v) end
  if t == 'table' then
    local morceaux = {}
    if estTableau(v) then
      for i = 1, #v do morceaux[i] = Json.encode(v[i]) end
      return '[' .. table.concat(morceaux, ',') .. ']'
    end
    local cles = {}
    for k in pairs(v) do
      if type(k) ~= 'string' then error('clé d\'objet non textuelle : ' .. tostring(k)) end
      cles[#cles + 1] = k
    end
    table.sort(cles)
    for i, k in ipairs(cles) do morceaux[i] = encoderChaine(k) .. ':' .. Json.encode(v[k]) end
    return '{' .. table.concat(morceaux, ',') .. '}'
  end
  error('type non encodable : ' .. t)
end

-- Décodage -------------------------------------------------------------------------------------------------------

local function invalide(i, message)
  error(string.format('JSON invalide (caractère %d) : %s', i, message), 0)
end

local function blancs(s, i)
  local _, fin = s:find('^[ \n\r\t]*', i)
  return fin + 1
end

local function caractereUtf8(c)
  if c < 0x80 then return string.char(c) end
  if c < 0x800 then return string.char(0xC0 + math.floor(c / 0x40), 0x80 + c % 0x40) end
  if c < 0x10000 then
    return string.char(0xE0 + math.floor(c / 0x1000), 0x80 + math.floor(c / 0x40) % 0x40, 0x80 + c % 0x40)
  end
  return string.char(0xF0 + math.floor(c / 0x40000), 0x80 + math.floor(c / 0x1000) % 0x40,
    0x80 + math.floor(c / 0x40) % 0x40, 0x80 + c % 0x40)
end

local SIMPLES = { b = '\b', f = '\f', n = '\n', r = '\r', t = '\t', ['"'] = '"', ['\\'] = '\\', ['/'] = '/' }

local function lireChaine(s, i)
  local morceaux, j = {}, i + 1
  while true do
    local fin = s:find('["\\]', j)
    if not fin then invalide(i, 'chaîne non fermée') end
    morceaux[#morceaux + 1] = s:sub(j, fin - 1)
    if s:sub(fin, fin) == '"' then return table.concat(morceaux), fin + 1 end
    local e = s:sub(fin + 1, fin + 1)
    if SIMPLES[e] then
      morceaux[#morceaux + 1] = SIMPLES[e]
      j = fin + 2
    elseif e == 'u' then
      local code = tonumber(s:sub(fin + 2, fin + 5), 16)
      if not code then invalide(fin, 'échappement \\u invalide') end
      j = fin + 6
      -- Paire de substitution UTF-16 (emoji et autres caractères hors du plan de base).
      if code >= 0xD800 and code <= 0xDBFF and s:sub(j, j + 1) == '\\u' then
        local bas = tonumber(s:sub(j + 2, j + 5), 16)
        if bas and bas >= 0xDC00 and bas <= 0xDFFF then
          code = 0x10000 + (code - 0xD800) * 0x400 + (bas - 0xDC00)
          j = j + 6
        end
      end
      morceaux[#morceaux + 1] = caractereUtf8(code)
    else
      invalide(fin, 'échappement inconnu')
    end
  end
end

local lireValeur

local function lireObjet(s, i)
  local objet = {}
  i = blancs(s, i + 1)
  if s:sub(i, i) == '}' then return objet, i + 1 end
  while true do
    if s:sub(i, i) ~= '"' then invalide(i, 'clé attendue') end
    local cle
    cle, i = lireChaine(s, i)
    i = blancs(s, i)
    if s:sub(i, i) ~= ':' then invalide(i, '« : » attendu') end
    objet[cle], i = lireValeur(s, i + 1)
    i = blancs(s, i)
    local c = s:sub(i, i)
    if c == '}' then return objet, i + 1 end
    if c ~= ',' then invalide(i, '« , » ou « } » attendu') end
    i = blancs(s, i + 1)
  end
end

local function lireTableau(s, i)
  local tableau = {}
  i = blancs(s, i + 1)
  if s:sub(i, i) == ']' then return tableau, i + 1 end
  while true do
    tableau[#tableau + 1], i = lireValeur(s, i)
    i = blancs(s, i)
    local c = s:sub(i, i)
    if c == ']' then return tableau, i + 1 end
    if c ~= ',' then invalide(i, '« , » ou « ] » attendu') end
    i = i + 1
  end
end

lireValeur = function(s, i)
  i = blancs(s, i)
  local c = s:sub(i, i)
  if c == '{' then return lireObjet(s, i) end
  if c == '[' then return lireTableau(s, i) end
  if c == '"' then return lireChaine(s, i) end
  if s:sub(i, i + 3) == 'true' then return true, i + 4 end
  if s:sub(i, i + 4) == 'false' then return false, i + 5 end
  if s:sub(i, i + 3) == 'null' then return Json.null, i + 4 end
  local nombre = s:match('^-?%d+%.?%d*[eE]?[-+]?%d*', i)
  local valeur = nombre and tonumber(nombre)
  if not valeur then invalide(i, 'valeur attendue') end
  return valeur, i + #nombre
end

function Json.decode(s)
  if type(s) ~= 'string' then invalide(0, 'pas une chaîne') end
  local valeur, i = lireValeur(s, 1)
  i = blancs(s, i)
  if i <= #s then invalide(i, 'texte après la valeur') end
  return valeur
end

return Json
