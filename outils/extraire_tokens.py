# -*- coding: utf-8 -*-
"""
extraire_tokens.py -- la table des tokens BASIC du PC-E500S, LUE DANS L'IMAGE ROM.

Pourquoi un script et non une table recopiee : une table exhaustive recopiee a la
main finit toujours par diverger de sa source. Celle-ci se regenere depuis rom83.bin
et se recoupe a chaque execution avec le carnet releve a la main
(SC62015Disassembler/Data/BasicTokens.csv) : deux sources independantes.

Ce qui est lu (adresses de la ROM 8.3, image plate mappee en 0C0000h) :
  0F52DCh  table de mots-cles : longueur 1 o + nom ASCII + token 1 o, groupes par
           initiale fermes par un octet 00 ; fin en 0F570Ah
  0F4FD1h  table de repartition : 256 entrees de 3 octets indexees par le token ;
           le quartet haut du 3e octet est un DRAPEAU, lu par les deux resolveurs :
             0F58D8h (test 080h en 0F58E5h) instruction -> routine = adresse
             0F590Bh (test 040h en 0F591Bh) fonction    -> routine = adresse + 3
           Une entree 000000h = aucune routine (le resolveur rend alors 0F5960h,
           qui fait « mv a,00Ah / sc / retf » : erreur 10).

Usage :
  python extraire_tokens.py [rom83.bin] [sortie.csv] [fragment.md]
"""
import csv
import os
import sys

ICI = os.path.dirname(os.path.abspath(__file__))
ROM = sys.argv[1] if len(sys.argv) > 1 else r'C:\Claude\SC62015Disassembler\Docs\ROM\rom83.bin'
CSV_OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ICI, '..', 'donnees', 'tokens-rom83.csv')
MD_OUT = sys.argv[3] if len(sys.argv) > 3 else os.path.join(ICI, '..', 'donnees', 'tokens-rom83.md')
CARNET = r'C:\Claude\SC62015Disassembler\Data\BasicTokens.csv'

BASE = 0x0C0000
KW_DEBUT, KW_FIN = 0x0F52DC, 0x0F570B
DISP = 0x0F4FD1

rom = open(ROM, 'rb').read()
if len(rom) != 0x40000:
    sys.exit(f'image inattendue : {len(rom)} octets (256 Ko attendus)')
if rom[KW_DEBUT - BASE:KW_DEBUT - BASE + 5] != b'\x03ASC\xD0':
    sys.exit("0F52DCh ne porte pas 03 'ASC' D0 : ce n'est pas la ROM 8.3 du PC-E500S")


def octet(a):
    return rom[a - BASE]


# --- table de mots-cles, lecture STRICTEMENT sequentielle ------------------
# Le token de RESERVED vaut 00 : seule la position le distingue de l'octet 00
# qui ferme un groupe (Docs/Synthese/BASIC-en-ROM.md §2).
mots = []
a = KW_DEBUT
while a < KW_FIN:
    n = octet(a)
    if n == 0:
        a += 1
        continue
    nom = rom[a - BASE + 1:a - BASE + 1 + n].decode('ascii')
    mots.append((octet(a + 1 + n), nom, a))
    a += n + 2

# --- table de repartition ---------------------------------------------------
def entree(t):
    e = DISP + 3 * t
    return octet(e) | octet(e + 1) << 8 | octet(e + 2) << 16


def nature(v):
    fl, adr = v >> 20, v & 0xFFFFF
    if v == 0:
        return 'aucune entree', ''
    if fl & 0x8 and fl & 0x4:
        return 'instruction et fonction', f'{adr:05X} / {adr + 3:05X}'
    if fl & 0x8:
        return 'instruction', f'{adr:05X}'
    if fl & 0x4:
        return 'fonction', f'{adr + 3:05X}'
    return f'drapeau {fl:X} inconnu', f'{adr:05X}'


# --- recoupement avec le carnet ---------------------------------------------
carnet = {}
if os.path.exists(CARNET):
    lignes = (l for l in open(CARNET, encoding='utf-8') if not l.startswith('#'))
    for r in csv.DictReader(lignes):
        if r['machine'] == '500S':
            carnet[r['name']] = r

ecarts = []
lignes_csv = []
for tok, nom, impl in sorted(mots):
    v = entree(tok)
    nat, rout = nature(v)
    c = carnet.get(nom)
    accord = (c is not None and int(c['code'], 16) == tok and c['impl'].upper() == f'{impl:05X}'
              and (c['exec'].upper() in rout.replace(' ', '').split('/')))
    if c is not None and not accord:
        ecarts.append((nom, c['exec'], rout or '-'))
    lignes_csv.append([f'{tok:02X}', nom, nat, f'{v >> 20:X}', f'{impl:05X}', f'{v:06X}', rout,
                       c['exec'] if c else '', 'oui' if accord else 'non'])

with open(CSV_OUT, 'w', newline='', encoding='utf-8') as f:
    w = csv.writer(f)
    w.writerow(['code', 'mot_cle', 'nature', 'drapeau', 'table_mots_cles', 'repartition_brute',
                'routine', 'carnet_exec', 'accord_carnet'])
    w.writerows(lignes_csv)

connus = {t for t, _, _ in mots}
sans_nom = [(t, entree(t)) for t in range(256) if t not in connus and entree(t) != 0]
libres = [t for t in range(256) if t not in connus and entree(t) == 0]

with open(MD_OUT, 'w', encoding='utf-8', newline='\n') as f:
    f.write('| Code | Mot-clé | Nature | Drapeau | Table des mots-clés | Routine |\n')
    f.write('|---|---|---|---|---|---|\n')
    for code, nom, nat, fl, impl, brut, rout, _, _ in lignes_csv:
        if nat == 'aucune entree':
            nat_md, rout_md = 'aucune entrée', '— (`0F5960h`, erreur 10)'
        else:
            nat_md, rout_md = nat, ' / '.join(f'`0{x.strip()}h`' for x in rout.split('/'))
        f.write(f'| `{code}h` | `{nom}` | {nat_md} | `{fl}` | `0{impl}h` | {rout_md} |\n')

print(f'{len(mots)} mots-cles, fin de table en {a:06X}h', file=sys.stderr)
compte = {}
for l in lignes_csv:
    compte[l[2]] = compte.get(l[2], 0) + 1
print('natures :', compte, file=sys.stderr)
print(f'carnet : {len(lignes_csv) - len(ecarts)} accords, {len(ecarts)} ecarts', file=sys.stderr)
for e in ecarts:
    print('   ecart :', e, file=sys.stderr)
print('repartition sans mot-cle :', ', '.join(f'{t:02X}h -> {v:06X}' for t, v in sans_nom), file=sys.stderr)
print(f'tokens libres ({len(libres)}) :', ' '.join(f'{t:02X}' for t in libres), file=sys.stderr)
