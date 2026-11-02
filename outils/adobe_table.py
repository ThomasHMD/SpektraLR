"""Tables RGB des profils créatifs Lightroom / Camera Raw : écriture, relecture, et les deux fonctions d'Adobe qui
entourent la table (gamma 1,8 de ProPhoto, courbe de tons ACR3 appliquée « RGBTone »).

D'après le DNG SDK d'Adobe 1.7.1 (dng_big_table.cpp : dng_rgb_table::PutStream, EncodeAsBinary, EncodeAsString ;
dng_color_space.cpp : dng_function_GammaEncode_1_8 ; dng_reference.cpp : RefBaselineRGBTone ; dng_render.cpp :
dng_tone_curve_acr3_default). Détail et vérifications : recherche/profils-lightroom.md.
"""
import hashlib
import re
import struct
import zlib

import numpy as np

# base 85 d'Adobe : mots de 4 octets petit-boutistes, chiffre de poids faible d'abord
ALPHABET = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.-:+=^!/*?`\'|()[]{}@%$#'
PROPHOTO, GAMMA_18, GAMUT_CLIP = 2, 2, 0


# --- la table ------------------------------------------------------------------------------------------------------

def _identite(n):
    return np.array([(i * 0xFFFF + (n >> 1)) // (n - 1) for i in range(n)], np.int64)


def table_binaire(t, prim=PROPHOTO, gamma=GAMMA_18, gamut=GAMUT_CLIP, amin=0.0, amax=2.0):
    """t : (N, N, N, 3) dans [0, 1], axes [r][g][b] (b le plus rapide), valeurs encodées dans le gamma de la table."""
    n = t.shape[0]
    nop = _identite(n)
    q = np.rint(np.clip(t, 0, 1) * 65535).astype(np.int64)
    q[..., 0] -= nop[:, None, None]
    q[..., 1] -= nop[None, :, None]
    q[..., 2] -= nop[None, None, :]
    return (struct.pack('<4I', 1, 1, 3, n) + (q & 0xFFFF).astype('<u2').tobytes()
            + struct.pack('<3I2d', prim, gamma, gamut, amin, amax))


def encoder(raw):
    """Bloc binaire → texte de l'attribut crs:Table_<empreinte>."""
    blob = struct.pack('<I', len(raw)) + zlib.compress(raw, zlib.Z_DEFAULT_COMPRESSION)
    n, p, out = len(blob), blob + b'\0\0\0', []
    for i in range(0, n, 4):
        x = struct.unpack('<I', p[i:i + 4])[0]
        for _ in range(min(4, n - i) + 1):
            out.append(ALPHABET[x % 85])
            x //= 85
    return ''.join(out)


def empreinte(raw):
    return hashlib.md5(raw).hexdigest().upper()


def decoder(texte):
    """Texte → (table (N, N, N, 3) dans [0, 1], en-tête). L'inverse exact d'encoder() et de table_binaire()."""
    valeurs = {c: i for i, c in enumerate(ALPHABET)}
    octets = bytearray()
    for i in range(0, len(texte), 5):
        bloc = texte[i:i + 5]
        x = 0
        for c in reversed(bloc):
            x = x * 85 + valeurs[c]
        octets += struct.pack('<I', x)[:len(bloc) - 1]
    taille = struct.unpack('<I', octets[:4])[0]
    raw = zlib.decompress(bytes(octets[4:]))
    if len(raw) != taille:
        raise ValueError(f'taille annoncée {taille}, lue {len(raw)}')
    genre, version, dims, n = struct.unpack('<4I', raw[:16])
    if (genre, version, dims) != (1, 1, 3):
        raise ValueError(f'en-tête inattendu {(genre, version, dims)}')
    q = np.frombuffer(raw[16:16 + 6 * n ** 3], '<u2').astype(np.int64).reshape(n, n, n, 3)
    nop = _identite(n)
    q[..., 0] += nop[:, None, None]
    q[..., 1] += nop[None, :, None]
    q[..., 2] += nop[None, None, :]
    prim, gamma, gamut, amin, amax = struct.unpack('<3I2d', raw[16 + 6 * n ** 3:16 + 6 * n ** 3 + 28])
    entete = dict(n=n, primaires=prim, gamma=gamma, gamut=gamut, quantite_min=amin, quantite_max=amax,
                  empreinte=empreinte(raw))
    return (q & 0xFFFF) / 65535.0, entete


def grille(n=32):
    """Les nœuds de la table, axes [r][g][b] : (N, N, N, 3) dans [0, 1], aux valeurs exactes de l'identité d'Adobe
    (une table qui rend la grille telle quelle ne stocke que des zéros)."""
    c = _identite(n) / 65535.0
    return np.stack(np.meshgrid(c, c, c, indexing='ij'), -1)


# --- gamma 1,8 d'Adobe (ProPhoto) ----------------------------------------------------------------------------------

_X1, _Y1, _S0, _S1 = 8.2118790552e-4, 0.019310851, 32.0, 13.064306598


def _hermite(x, x0, y0, s0, x1, y1, s1):
    h = x1 - x0
    t = (x - x0) / h
    t2, t3 = t * t, t * t * t
    return ((2 * t3 - 3 * t2 + 1) * y0 + (t3 - 2 * t2 + t) * h * s0
            + (-2 * t3 + 3 * t2) * y1 + (t3 - t2) * h * s1)


def gamma18_encoder(x):
    x = np.clip(np.asarray(x, float), 0.0, 1.0)
    return np.where(x <= _X1, _hermite(x, 0.0, 0.0, _S0, _X1, _Y1, _S1), np.power(x, 1 / 1.8))


_PIED = np.linspace(0.0, _X1, 4097)
_PIED_Y = _hermite(_PIED, 0.0, 0.0, _S0, _X1, _Y1, _S1)


def gamma18_decoder(y):
    y = np.clip(np.asarray(y, float), 0.0, 1.0)
    return np.where(y < _Y1, np.interp(y, _PIED_Y, _PIED), np.power(y, 1.8))


# --- courbe de tons ACR3 (base des profils Adobe Standard) ---------------------------------------------------------

def lire_acr3(dng_render_cpp):
    """La table de 1 025 points de dng_tone_curve_acr3_default::Evaluate, lue dans dng_render.cpp du DNG SDK."""
    texte = open(dng_render_cpp, encoding='latin-1').read()
    debut = texte.index('dng_tone_curve_acr3_default::Evaluate (')
    bloc = texte[texte.index('{', texte.index('kTable', debut)):]
    bloc = bloc[:bloc.index('}')]
    t = np.array([float(v) for v in re.findall(r'[-+]?\d*\.\d+(?:[eE][-+]?\d+)?', bloc)])
    if len(t) != 1025 or t[0] != 0.0 or abs(t[-1] - 1.0) > 1e-6 or np.any(np.diff(t) <= 0):
        raise ValueError(f'table ACR3 inattendue ({len(t)} points)')
    return t


class CourbeRGBTone:
    """La courbe de tons appliquée comme RefBaselineRGBTone : la courbe sur le canal le plus fort et le plus faible,
    le canal du milieu interpolé au même rapport (la teinte est gardée). L'inverse est exact : l'ordre des canaux est
    conservé par une courbe croissante."""

    def __init__(self, table):
        self.y = np.asarray(table, float)
        self.x = np.linspace(0.0, 1.0, len(self.y))

    def directe(self, rgb):
        return self._appliquer(rgb, lambda v: np.interp(v, self.x, self.y))

    def inverse(self, rgb):
        return self._appliquer(rgb, lambda v: np.interp(v, self.y, self.x))

    @staticmethod
    def _appliquer(rgb, f):
        rgb = np.clip(np.asarray(rgb, float), 0.0, 1.0)
        haut, bas = rgb.max(-1), rgb.min(-1)
        fh, fb = f(haut), f(bas)
        ecart = (haut - bas)[..., None]
        rapport = np.where(ecart > 0, (rgb - bas[..., None]) / np.where(ecart > 0, ecart, 1.0), 0.0)
        return fb[..., None] + (fh - fb)[..., None] * rapport
