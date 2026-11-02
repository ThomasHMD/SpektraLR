#!/usr/bin/env python3
"""Contrôles des tables et des profils (sans Lightroom, sans spektrafilm) :

    python3 tests/test_profils.py [dossier des profils]

Codec (aller-retour, identité, empreinte), gamma 1,8 d'Adobe, et chaque profil livré relu : empreinte = nom de la
table, en-tête attendu, preset qui cite le bon UUID de profil.
"""
import re
import sys
from pathlib import Path

ICI = Path(__file__).resolve().parent
sys.path.insert(0, str(ICI.parent / 'outils'))
sys.dont_write_bytecode = True

import numpy as np  # noqa: E402

import adobe_table as A  # noqa: E402

n = 0


def verifie(condition, message):
    global n
    n += 1
    if not condition:
        raise SystemExit('ÉCHEC : ' + message)


# codec
rng = np.random.default_rng(7)
t = rng.random((32, 32, 32, 3))
raw = A.table_binaire(t)
relu, entete = A.decoder(A.encoder(raw))
verifie(len(raw) == 16 + 6 * 32 ** 3 + 28, 'taille du bloc binaire')
verifie(np.abs(relu - t).max() <= 0.5 / 65535 + 1e-12, 'aller-retour de la table')
verifie(entete['empreinte'] == A.empreinte(raw) and entete['empreinte'].isupper(), 'empreinte MD5 en majuscules')
verifie((entete['n'], entete['primaires'], entete['gamma'], entete['quantite_max']) == (32, 2, 2, 2.0), 'en-tête')
verifie(not any(A.table_binaire(A.grille(32))[16:16 + 6 * 32 ** 3]), 'table identité = zéros')
verifie(all(c in A.ALPHABET for c in A.encoder(raw)) and len(set(A.ALPHABET)) == 85, 'alphabet base 85')

# gamma 1,8
y = np.linspace(0, 1, 10001)
verifie(np.abs(A.gamma18_encoder(A.gamma18_decoder(y)) - y).max() < 1e-8, 'gamma 1,8 aller-retour')
verifie(abs(A.gamma18_encoder(0.18) - 0.18 ** (1 / 1.8)) < 1e-12, 'gamma 1,8 hors pied')

# RGBTone : une courbe quelconque croissante, inversée exactement
courbe = A.CourbeRGBTone(np.linspace(0, 1, 1025) ** 0.6)
x = rng.random((5000, 3))
verifie(np.abs(courbe.inverse(courbe.directe(x)) - x).max() < 1e-9, 'RGBTone inverse exacte')
verifie(np.allclose(courbe.directe(np.full(3, 0.3)), 0.3 ** 0.6), 'RGBTone sur un gris')

# profils livrés
dossier = Path(sys.argv[1]) if len(sys.argv) > 1 else ICI.parent / 'presets' / 'SpektraLR'
profils = sorted((dossier / 'Profils').glob('*.xmp'))
verifie(len(profils) == 20, f'{len(profils)} profils au lieu de 20')
uuids = {}
for p in profils:
    texte = p.read_text(encoding='utf-8')
    md5 = re.search(r'crs:RGBTable="([0-9A-F]{32})"', texte).group(1)
    table, e = A.decoder(re.search(r'crs:Table_' + md5 + r'="([^"]+)"', texte).group(1))
    verifie(e['empreinte'] == md5 and e['n'] == 32 and e['primaires'] == 2 and e['gamma'] == 2, f'{p.name} : table')
    verifie('crs:CameraProfile="Adobe Standard"' in texte and 'Andrea Volpato' in texte, f'{p.name} : base, crédit')
    uuids[p.stem] = re.search(r'crs:UUID="([0-9A-F]{32})"', texte).group(1)
    gris = table[15, 15, 15]
    verifie(np.ptp(gris) < 0.02, f'{p.name} : un gris reste neutre ({np.round(gris, 3)})')
for p in sorted((dossier / 'Presets').glob('*.xmp')):
    look = re.search(r'<crs:Look>.*?crs:UUID="([0-9A-F]{32})"', p.read_text(encoding='utf-8'), re.S).group(1)
    verifie(look == uuids.get(p.stem), f'{p.name} : le preset ne cite pas son profil')
for f in ('SPEKTRAFILM_LICENSE.txt', 'LICENSE-CC-BY-SA-4.0.txt', 'CHANGELOG.txt'):
    verifie((dossier / f).exists(), f'{f} manque')

print(f'{n} contrôles OK')
