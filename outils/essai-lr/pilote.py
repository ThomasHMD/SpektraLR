#!/usr/bin/env python3
"""Envoie une commande au module d'essai (Pilote.lua) dans Lightroom et affiche sa réponse.

    python3 pilote.py '{"action": "ping"}'
    python3 pilote.py @commande.json
"""
import json
import subprocess
import sys
import time
import uuid
from pathlib import Path

DOSSIER = Path.home() / 'Library/Application Support/Adobe/Lightroom/Modules/SpektraLR-Essai.lrplugin/pilote'


def envoyer(cmd, attente=900):
    DOSSIER.mkdir(parents=True, exist_ok=True)
    cmd = dict(cmd, id=uuid.uuid4().hex[:8])
    reponse = DOSSIER / 'reponse.json'
    reponse.unlink(missing_ok=True)
    tmp = DOSSIER / 'commande.tmp'
    tmp.write_text(json.dumps(cmd, ensure_ascii=False), encoding='utf-8')
    tmp.rename(DOSSIER / 'commande.json')
    fin, reveil = time.time() + attente, time.time() + 3
    while time.time() < fin:
        if reveil and time.time() > reveil:  # pilote endormi : le lien lightroom:// le démarre
            subprocess.run(['open', '-g', 'lightroom://com.thomashammoudi.spektralr.essai/demarrer'])
            reveil = None
        if reponse.exists():
            r = json.loads(reponse.read_text(encoding='utf-8'))
            if r.get('id') == cmd['id']:
                reponse.unlink()
                return r
        time.sleep(0.3)
    (DOSSIER / 'commande.json').unlink(missing_ok=True)
    raise TimeoutError(f'pas de réponse de Lightroom en {attente} s ({cmd["action"]})')


if __name__ == '__main__':
    a = sys.argv[1]
    cmd = json.loads(Path(a[1:]).read_text() if a.startswith('@') else a)
    r = envoyer(cmd, attente=float(sys.argv[2]) if len(sys.argv) > 2 else 900)
    print(json.dumps(r, ensure_ascii=False, indent=1))
    sys.exit(0 if r.get('ok') else 1)
