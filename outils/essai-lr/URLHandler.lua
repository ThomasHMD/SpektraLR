-- Lightroom appelle URLHandler(url) pour tout lien lightroom://com.thomashammoudi.spektralr.essai/… (lu dans
-- LightroomCustomUrlHandling.lua de Lightroom) : pilote.py en ouvre un si le pilote ne répond pas.
return {
  URLHandler = function(url)
    require('Pilote').demarrer()
  end,
}
