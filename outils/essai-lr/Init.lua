-- Démarre le pilote. Journal du SDK : ~/Documents/LrClassicLogs/SpektraLR-Essai.log.
local journal = import 'LrLogger'('SpektraLR-Essai')
journal:enable('logfile')
journal:info('Init.lua, io : ' .. type(io))
local fait, erreur = pcall(function() require('Pilote').demarrer() end)
journal:info(fait and 'pilote démarré' or ('erreur au démarrage : ' .. tostring(erreur)))
