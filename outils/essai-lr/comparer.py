#!/usr/bin/env python3
"""Lightroom applique-t-il la table comme prévu ? Prend l'export TIFF ProPhoto 16 bits d'une copie en Adobe Standard,
lui applique la table du profil (interpolation trilinéaire, comme fabriquer_profils la relit), et compare au même
export fait par Lightroom avec le profil. Écart en ΔE 2000, à côté de l'écart que le profil crée.

    python comparer.py <dossier des exports> <dossier des profils>   (python du venv de spektrafilm)
"""
import sys
from pathlib import Path

import colour
import numpy as np
import tifffile
from scipy.interpolate import RegularGridInterpolator

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import fabriquer_profils as F  # noqa: E402

PAIRES = {'chaine-portra-400.tif': 'Kodak Portra 400.xmp', 'chaine-velvia-100.tif': 'Fujifilm Velvia 100.xmp'}


def lire(chemin):
    return tifffile.imread(chemin)[..., :3].astype(np.float64) / 65535


def lab(code):
    lin = colour.RGB_to_XYZ(code ** 1.8, 'ProPhoto RGB', illuminant=colour.CCS_ILLUMINANTS['CIE 1931 2 Degree Standard Observer']['D50'])
    return colour.XYZ_to_Lab(lin, colour.CCS_ILLUMINANTS['CIE 1931 2 Degree Standard Observer']['D50'])


def stats(de):
    return f'moyenne {de.mean():.2f}, 95 % sous {np.percentile(de, 95):.2f}, max {de.max():.1f}'


def main():
    exports, profils = Path(sys.argv[1]), Path(sys.argv[2])
    adobe = lire(exports / 'chaine-adobe.tif')
    lab_adobe = lab(adobe)
    for tif, xmp in PAIRES.items():
        table = F.relire(profils / xmp)
        c = np.linspace(0, 1, table.shape[0])
        prevu = RegularGridInterpolator((c, c, c), table)(adobe.reshape(-1, 3)).reshape(adobe.shape)
        lr = lire(exports / tif)
        lab_lr = lab(lr)
        print(f'{xmp[:-4]} : Lightroom contre ma table : {stats(colour.delta_E(lab(prevu), lab_lr, method="CIE 2000"))}')
        print(f'{" " * len(xmp[:-4])}   (écart créé par le profil : {stats(colour.delta_E(lab_adobe, lab_lr, method="CIE 2000"))})')


if __name__ == '__main__':
    main()
