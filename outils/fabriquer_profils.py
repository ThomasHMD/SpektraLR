#!/usr/bin/env python3
"""Fabrique les profils créatifs et les presets de développement Lightroom de SpektraLR, à partir de spektrafilm.

Pour chaque film, une table 3D 32³ en ProPhoto γ 1,8, l'espace où Lightroom applique la table d'un profil créatif.
Le profil impose Adobe Standard comme base (crs:CameraProfile) ; la table reçoit donc ce rendu, et :
  1. défait le gamma 1,8, puis la courbe de tons ACR3 d'Adobe Standard (inverse exact de son application « RGBTone ») ;
  2. ramène le gris que Lightroom rend à L* 50 sur le gris de 18 % de la scène ;
  3. passe la scène dans spektrafilm (mode table : effets spatiaux et aléatoires coupés) : négatif tiré sur le papier
     que conseille le film, ou diapositive scannée ;
  4. rend le tirage relatif à la luminance de son blanc (le papier vierge sort à L* 100 et garde sa teinte, le noir
     n'est pas recalé), la scène décalée pour que le gris de 18 % sorte à 118/255 (L* 49,6), comme le rendu
     « relatif_gris » des cibles du X-T4, mais sans adaptation chromatique (voir Tirage) ;
  5. réencode en γ 1,8.
Quantité 0 = Adobe Standard. Format des fichiers : DNG SDK d'Adobe, voir recherche/profils-lightroom.md.

  python fabriquer_profils.py --dng-render <dng_render.cpp du DNG SDK> --sortie <dossier> [--films id1,id2]

À lancer avec le Python où spektrafilm est installé (0.3.4). dng_render.cpp vient du DNG SDK d'Adobe
(https://helpx.adobe.com/camera-raw/desktop/dng-and-file-formats/digital-negative.html) : on n'y lit que la table de la
courbe ACR3, qui n'est pas redistribuée ici.
"""
import argparse
import hashlib
import re
import shutil
import sys
from pathlib import Path
from xml.sax.saxutils import escape

import numpy as np

import adobe_table as A

N = 32
L_GRIS = 49.64            # L* de 118/255 : où sort le gris de 18 % du tirage (rendu relatif_gris)
L_GRIS_ADOBE = 50.0       # L* du gris que Lightroom rend « bien exposé » : il devient le gris de 18 % de la scène
GROUPE = 'SpektraLR'
DEPOT = 'https://github.com/ThomasHMD/SpektraLR'
SPEKTRAFILM = 'https://github.com/andreavolpato/spektrafilm'
COPYRIGHT = ('Derived from spektrafilm by Andrea Volpato (github.com/andreavolpato/spektrafilm), CC BY-SA 4.0. '
             'Modified by Thomas Hammoudi (SpektraLR).')
DESCRIPTION = ('Film modeling powered by spektrafilm (Andrea Volpato, ' + SPEKTRAFILM + '), licensed CC BY-SA 4.0 '
               '(https://creativecommons.org/licenses/by-sa/4.0/). Modified by Thomas Hammoudi: input = Adobe Standard '
               'rendering with its ACR3 tone curve undone, print relative to paper white, 32x32x32 table. ' + DEPOT)

PAPIER_KODAK, PAPIER_FUJI, PAPIER_CINE = 'kodak_portra_endura', 'fujifilm_crystal_archive_typeii', 'kodak_2383'
# id spektrafilm, nom affiché, papier conseillé (None = diapositive, scannée), sensibilité (pour le grain du preset)
FILMS = [
    ('kodak_portra_160', 'Kodak Portra 160', PAPIER_KODAK, 160),
    ('kodak_portra_400', 'Kodak Portra 400', PAPIER_KODAK, 400),
    ('kodak_portra_800', 'Kodak Portra 800', PAPIER_KODAK, 800),
    ('kodak_portra_800_push1', 'Kodak Portra 800 Push 1', PAPIER_KODAK, 1600),
    ('kodak_portra_800_push2', 'Kodak Portra 800 Push 2', PAPIER_KODAK, 3200),
    ('kodak_ektar_100', 'Kodak Ektar 100', PAPIER_KODAK, 100),
    ('kodak_gold_200', 'Kodak Gold 200', PAPIER_KODAK, 200),
    ('kodak_ultramax_400', 'Kodak UltraMax 400', PAPIER_KODAK, 400),
    ('fujifilm_c200', 'Fujifilm C200', PAPIER_FUJI, 200),
    ('fujifilm_pro_400h', 'Fujifilm Pro 400H', PAPIER_FUJI, 400),
    ('fujifilm_xtra_400', 'Fujifilm X-Tra 400', PAPIER_FUJI, 400),
    ('kodak_vision3_50d', 'Kodak Vision3 50D', PAPIER_CINE, 50),
    ('kodak_vision3_200t', 'Kodak Vision3 200T', PAPIER_CINE, 200),
    ('kodak_vision3_250d', 'Kodak Vision3 250D', PAPIER_CINE, 250),
    ('kodak_vision3_500t', 'Kodak Vision3 500T', PAPIER_CINE, 500),
    ('kodak_verita_200d', 'Kodak Verita 200D', PAPIER_CINE, 200),
    ('fujifilm_provia_100f', 'Fujifilm Provia 100F', None, 100),
    ('fujifilm_velvia_100', 'Fujifilm Velvia 100', None, 100),
    ('kodak_ektachrome_100', 'Kodak Ektachrome E100', None, 100),
    ('kodak_kodachrome_64', 'Kodak Kodachrome 64', None, 64),
]
NOMS_PAPIERS = {PAPIER_KODAK: 'Kodak Portra Endura', PAPIER_FUJI: 'Fujifilm Crystal Archive II',
                PAPIER_CINE: 'Kodak Vision 2383'}

# grain de Lightroom par sensibilité : Quantité, Taille, Rugosité (pas physique : à l'œil, d'après les presets Film
# d'Adobe, 30 / 25 / 25)
GRAINS = [(64, (10, 15, 40)), (100, (12, 18, 40)), (250, (18, 22, 45)), (400, (25, 25, 50)), (800, (35, 30, 55)),
          (1600, (45, 35, 60)), (99999, (55, 40, 65))]


# --- le calcul -----------------------------------------------------------------------------------------------------

def pipeline(film, papier):
    from spektrafilm.runtime.params_builder import digest_params, init_params
    from spektrafilm.runtime.pipeline import SimulationPipeline
    from spektrafilm.utils.gamut_compression import InputGamutCompressSpec, OutputGamutCompressSpec
    # Réglages de spektrafilm-lut (BundleBuilder._make_pipeline, défauts de BundleSpec), plus le scan des diapositives,
    # que le CLI 0.3.4 ne sait pas faire.
    p = init_params(film_profile=film, print_profile=papier or PAPIER_KODAK)
    p.debug.lut_mode = True
    p.io.input_color_space = p.io.output_color_space = 'ProPhoto RGB'
    p.io.input_cctf_decoding = p.io.output_cctf_encoding = False
    p.io.input_gamut_compress = InputGamutCompressSpec()
    p.io.output_gamut_compress = OutputGamutCompressSpec(algorithm='cam16ucs')
    if papier is None:
        p.io.scan_film = True
    return SimulationPipeline(digest_params(p))


def _xyz(rgb):
    import colour
    return colour.RGB_to_XYZ(rgb, 'ProPhoto RGB', apply_cctf_decoding=False)


def _lstar(rgb):
    y = _xyz(rgb)[..., 1]
    return np.where(y > 216 / 24389, 116 * np.cbrt(y) - 16, y * 24389 / 27)


class Tirage:
    """Scène (ProPhoto linéaire, gris = 0,18) → tirage relatif à la luminance de son blanc (ProPhoto linéaire).

    Le blanc du support ne règle que la luminance (Y du papier vierge → 1), pas la couleur : spektrafilm filtre déjà le
    tirage pour que le gris soit neutre, comme le labo. Une adaptation chromatique au blanc du support (Bradford, rendu
    « relatif » des cibles du X-T4) refroidissait tout le tirage sur les papiers au blanc chaud (2383 : gris à b* −5)."""

    def __init__(self, film, papier):
        self.pipe = pipeline(film, papier)
        # blanc du support : la scène très au-dessus du gris (palier de la rampe : papier sans image, ou diapo claire)
        blanc = self._brut(np.full((1, 1, 3), 0.18 * 2 ** 12))[0, 0]
        self.echelle = 1.0 / _xyz(blanc)[1]
        self.blanc_absolu = blanc
        # décalage d'exposition qui amène le gris de 18 % à L* 49,6 une fois rendu relatif
        bas, haut = -4.0, 4.0
        for _ in range(40):
            milieu = (bas + haut) / 2
            if _lstar(self.relatif(np.full((1, 1, 3), 0.18 * 2 ** milieu)))[0, 0] < L_GRIS:
                bas = milieu
            else:
                haut = milieu
        self.decalage = (bas + haut) / 2

    def _brut(self, scene):
        return np.asarray(self.pipe.process(np.asarray(scene, np.float32)), float)

    def relatif(self, scene):
        return self._brut(scene) * self.echelle

    def __call__(self, scene):
        return self.relatif(scene * 2 ** self.decalage)


def table_film(tirage, tone):
    """Table (N, N, N, 3) en ProPhoto γ 1,8 : rendu Adobe Standard → tirage."""
    rendu = A.gamma18_decoder(A.grille(N))
    gris_avant_courbe = tone.inverse(np.full(3, _y_de_lstar(L_GRIS_ADOBE)))[0]
    scene = tone.inverse(rendu) * (0.18 / gris_avant_courbe)
    sortie = tirage(scene.reshape(N, N * N, 3)).reshape(N, N, N, 3)
    return A.gamma18_encoder(np.clip(sortie, 0.0, 1.0))


def _y_de_lstar(l):
    return ((l + 16) / 116) ** 3


# --- les fichiers --------------------------------------------------------------------------------------------------

def uuid(*parties):
    return hashlib.md5('/'.join(('spektra-lr',) + parties).encode()).hexdigest().upper()


def _alt(balise, texte, retrait='   '):
    contenu = f'<rdf:li xml:lang="x-default">{escape(texte)}</rdf:li>' if texte else '<rdf:li xml:lang="x-default"/>'
    return (f'{retrait}<crs:{balise}>\n{retrait} <rdf:Alt>\n{retrait}  {contenu}\n'
            f'{retrait} </rdf:Alt>\n{retrait}</crs:{balise}>\n')


ENTETE = ('<x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP Core 7.0-c000 1.000000, 0000/00/00-00:00:00        ">\n'
          ' <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">\n'
          '  <rdf:Description rdf:about=""\n    xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"\n')
PIED = '  </rdf:Description>\n </rdf:RDF>\n</x:xmpmeta>\n'


def profil_xmp(nom, uuid_profil, table):
    raw = A.table_binaire(table)
    md5 = A.empreinte(raw)
    attributs = [
        ('PresetType', 'Look'), ('Cluster', ''), ('UUID', uuid_profil), ('SupportsAmount', 'True'),
        ('SupportsColor', 'True'), ('SupportsMonochrome', 'False'), ('SupportsHighDynamicRange', 'False'),
        ('SupportsNormalDynamicRange', 'True'), ('SupportsSceneReferred', 'True'),
        # la table défait la courbe d'Adobe Standard : rien à faire sur un JPEG ou un TIFF déjà rendus
        ('SupportsOutputReferred', 'False'), ('RequiresRGBTables', 'False'), ('CameraModelRestriction', ''),
        ('Copyright', COPYRIGHT), ('ContactInfo', DEPOT), ('Version', '18.0'), ('ProcessVersion', '15.4'),
        ('ConvertToGrayscale', 'False'), ('CameraProfile', 'Adobe Standard'), ('RGBTable', md5),
        ('Table_' + md5, A.encoder(raw)), ('HasSettings', 'True'),
    ]
    corps = ''.join(f'   crs:{k}="{escape(v, {chr(34): "&quot;"})}"\n' for k, v in attributs[:-1])
    corps += f'   crs:{attributs[-1][0]}="{attributs[-1][1]}">\n'
    return (ENTETE + corps + _alt('Name', nom) + _alt('ShortName', '') + _alt('SortName', '') + _alt('Group', GROUPE)
            + _alt('Description', DESCRIPTION) + PIED)


def preset_xmp(nom, uuid_preset, nom_profil, uuid_profil, grain):
    quantite, taille, rugosite = grain
    attributs = [
        ('PresetType', 'Normal'), ('Cluster', ''), ('UUID', uuid_preset), ('SupportsAmount2', 'True'),
        ('SupportsAmount', 'True'), ('SupportsColor', 'True'), ('SupportsMonochrome', 'False'),
        ('SupportsHighDynamicRange', 'False'), ('SupportsNormalDynamicRange', 'True'),
        ('SupportsSceneReferred', 'True'), ('SupportsOutputReferred', 'False'), ('RequiresRGBTables', 'False'),
        ('ShowInPresets', 'True'), ('ShowInQuickActions', 'False'), ('CameraModelRestriction', ''),
        ('Copyright', COPYRIGHT), ('ContactInfo', DEPOT), ('Version', '18.0'), ('ProcessVersion', '15.4'),
        ('GrainAmount', str(quantite)), ('GrainSize', str(taille)), ('GrainFrequency', str(rugosite)),
        ('HasSettings', 'True'),
    ]
    corps = ''.join(f'   crs:{k}="{escape(v, {chr(34): "&quot;"})}"\n' for k, v in attributs[:-1])
    corps += f'   crs:{attributs[-1][0]}="{attributs[-1][1]}">\n'
    look = ('   <crs:Look>\n    <rdf:Description\n'
            f'     crs:Name="{escape(nom_profil)}"\n     crs:Amount="1"\n     crs:Cluster=""\n'
            f'     crs:UUID="{uuid_profil}"\n     crs:SupportsMonochrome="false"\n'
            f'     crs:Copyright="{escape(COPYRIGHT)}"\n     crs:Stubbed="true">\n'
            + _alt('Group', GROUPE, '    ') + '    </rdf:Description>\n   </crs:Look>\n')
    return (ENTETE + corps + _alt('Name', nom) + _alt('ShortName', '') + _alt('SortName', '') + _alt('Group', GROUPE)
            + _alt('Description', DESCRIPTION) + look + PIED)


def grain_pour(iso):
    return next(g for seuil, g in GRAINS if iso <= seuil)


def relire(chemin):
    """Contrôle d'un profil écrit : l'empreinte est bien celle de la table, l'en-tête est celui attendu."""
    texte = Path(chemin).read_text(encoding='utf-8')
    md5 = re.search(r'crs:RGBTable="([0-9A-F]{32})"', texte).group(1)
    table, entete = A.decoder(re.search(r'crs:Table_' + md5 + r'="([^"]+)"', texte).group(1))
    attendu = dict(n=N, primaires=A.PROPHOTO, gamma=A.GAMMA_18, gamut=A.GAMUT_CLIP, quantite_min=0.0, quantite_max=2.0)
    if entete['empreinte'] != md5 or any(entete[k] != v for k, v in attendu.items()):
        raise ValueError(f'{chemin} : table mal écrite ({entete})')
    return table


def main():
    a = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    a.add_argument('--dng-render', required=True, help='dng_render.cpp du DNG SDK d\'Adobe (courbe ACR3)')
    a.add_argument('--sortie', required=True, help='dossier où écrire SpektraLR/Profils et SpektraLR/Presets')
    a.add_argument('--films', help='ids spektrafilm séparés par des virgules (défaut : tous)')
    args = a.parse_args()

    tone = A.CourbeRGBTone(A.lire_acr3(args.dng_render))
    choisis = set(args.films.split(',')) if args.films else None
    racine = Path(args.sortie) / GROUPE
    (racine / 'Profils').mkdir(parents=True, exist_ok=True)
    (racine / 'Presets').mkdir(parents=True, exist_ok=True)

    gris_adobe = A.gamma18_encoder(_y_de_lstar(L_GRIS_ADOBE))
    i_gris = int(round(gris_adobe * (N - 1)))
    print(f'{"film":<26}{"papier":<30}{"décalage":>9}{"blanc absolu L*":>17}{"gris rendu → L*":>17}')
    for film, nom, papier, iso in FILMS:
        if choisis and film not in choisis:
            continue
        tirage = Tirage(film, papier)
        table = table_film(tirage, tone)
        uuid_profil = uuid(film, papier or 'scan')
        chemin = racine / 'Profils' / f'{nom}.xmp'
        chemin.write_text(profil_xmp(nom, uuid_profil, table), encoding='utf-8')
        relu = relire(chemin)
        # contrôle : le nœud neutre le plus proche du gris L* 50 d'Adobe doit sortir près de L* 49,6
        l_noeud = _lstar(A.gamma18_decoder(relu[i_gris, i_gris, i_gris]))
        (racine / 'Presets' / f'{nom}.xmp').write_text(
            preset_xmp(nom, uuid('preset', film), nom, uuid_profil, grain_pour(iso)), encoding='utf-8')
        print(f'{nom:<26}{NOMS_PAPIERS.get(papier, "diapositive, scannée"):<30}{tirage.decalage:>+8.2f} IL'
              f'{float(_lstar(tirage.blanc_absolu)):>16.1f}{float(l_noeud):>17.1f}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
