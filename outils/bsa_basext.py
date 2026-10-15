#!/usr/bin/env python3
r"""bsa_basext.py -- .BAS <-> .BSA pour un programme qui emploie les mots-cles de BASEXT.

    python C:\Claude\BASEXT\outils\bsa_basext.py ..\essais\DWGLTEST.BAS     # -> .BSA
    python C:\Claude\BASEXT\outils\bsa_basext.py ..\essais\DWGLTEST.BSA     # -> .BAS
    python C:\Claude\BASEXT\outils\bsa_basext.py --table                    # la table seule

✅ DEPUIS LE 2026-10-15, « Sharp Basic Converter » CONNAIT LES EXTENSIONS : son option
   -k/--keywords <table.csv> ajoute aux 168 mots-cles de la ROM ceux d'un module
   (dans « main » depuis la fusion c62ad64, publie dans C:\sharp\SharpBasicConverter).
   Verifie contre
   BEXTTEST.BSA, enregistre par le PC-E500S BASEXT installe : identique A L'OCTET
   dans les deux sens. Cet outil n'est donc plus qu'un AIGUILLAGE :

   1. il lit les mots-cles dans src/BASEXT.ASM (les equ des tokens et la kw_table),
      jamais recopies : un seizieme mot-cle y est connu d'office ;
   2. il en ecrit la table, donnees/tokens-basext.csv, au format de
      Codes_BASIC_PC-E500S.csv -- c'est elle qu'on donne a « sharpbasic -k » ;
   3. il appelle sharpbasic, en CP437 dans les deux sens (aucun octet ne bouge) ;
   4. il VERIFIE par aller-retour binaire, comme avant.

   ⛔ Avant cette option, l'outil passait par des DOUBLURES : chaque mot-cle de
   BASEXT remplace par une fonction de la ROM absente du programme, puis l'octet de
   token corrige dans le .BSA. Ce procede, eprouve lui aussi contre la machine, est
   dans l'historique git (commit 9681dc3) ; il n'a plus de raison d'etre.

   Le convertisseur reproduit en outre deux regles de la machine (MODE-EMPLOI §1.2,
   §11) : la ROM est consultee AVANT l'extension, et une seule extension a la fois.
   Une table qui violerait l'une d'elles est refusee par sharpbasic lui-meme.
"""
import os
import re
import subprocess
import sys
import tempfile

ICI = os.path.dirname(os.path.abspath(__file__))
ASM = os.path.join(ICI, "..", "src", "BASEXT.ASM")
TABLE = os.path.normpath(os.path.join(ICI, "..", "donnees", "tokens-basext.csv"))

# L'executable : la variable SHARPBASIC s'il y en a une, sinon le premier de ces
# chemins qui connait --keywords (un executable anterieur au 2026-10-15 l'ignore ;
# il est essaye, puis ecarte).
CANDIDATS = [
    r"C:\sharp\SharpBasicConverter\sharpbasic.exe",
    r"C:\Claude\Sharp Basic Converter\Publish\sharpbasic.exe",
]


def erreur(m):
    print("ERREUR : " + m)
    sys.exit(1)


def mots_de_basext():
    r"""Les mots-cles et leurs tokens, LUS DANS src/BASEXT.ASM. On lit les deux
        choses qui les definissent :
           tk_dw:    equ   0D3H
           db      4,'DWGL',tk_dw        (dans kw_table)"""
    src = open(ASM, encoding="utf-8").read()
    equ = {m.group(1): int(m.group(2), 16) for m in
           re.finditer(r"^(tk_\w+):\s*equ\s+0?([0-9A-Fa-f]+)H", src, re.M)}
    table = {}
    for m in re.finditer(r"^\s*db\s+\d+,'([A-Z0-9$]+)',(tk_\w+)", src, re.M):
        nom, cle = m.group(1), m.group(2)
        if cle not in equ:
            erreur("BASEXT.ASM : %s sans equ" % cle)
        table[nom] = equ[cle]
    if not table:
        erreur("BASEXT.ASM : kw_table illisible")
    return table


def ecrire_table(mots):
    """donnees/tokens-basext.csv, au format de Codes_BASIC_PC-E500S.csv. Reecrite
       seulement si elle change, pour ne pas toucher sa date sans raison."""
    lignes = ["Code Hexa,Code Décimal,Instruction,Description"]
    for nom, code in sorted(mots.items(), key=lambda kv: kv[1]):
        lignes.append("0x%02X,%d,%s,BASEXT" % (code, code, nom))
    texte = "\r\n".join(lignes) + "\r\n"
    ancien = open(TABLE, encoding="utf-8", newline="").read() if os.path.exists(TABLE) else None
    if texte != ancien:
        with open(TABLE, "w", encoding="utf-8", newline="") as f:
            f.write(texte)
        print("table   : %s (%d mots-cles) -- %s" % (TABLE, len(mots),
              "creee" if ancien is None else "MISE A JOUR"))
    else:
        print("table   : %s (%d mots-cles)" % (TABLE, len(mots)))


def trouver_sharpbasic():
    candidats = ([os.environ["SHARPBASIC"]] if os.environ.get("SHARPBASIC") else []) + CANDIDATS
    for exe in candidats:
        if not os.path.exists(exe):
            continue
        r = subprocess.run([exe, "--help"], capture_output=True, text=True, errors="replace")
        if "--keywords" in r.stdout:
            return exe
    erreur("aucun sharpbasic ne connait --keywords. Chemins essayes :\n   "
           + "\n   ".join(candidats)
           + "\nRepublier Sharp Basic Converter (deploy.ps1, branche main),"
             " ou designer l'executable par la variable SHARPBASIC.")


def sharpbasic(exe, *args):
    r = subprocess.run([exe, *args, "-k", TABLE, "-f"],
                       capture_output=True, text=True, errors="replace")
    if r.returncode:
        erreur("sharpbasic %s :\n%s%s" % (args[0], r.stdout, r.stderr))
    # un FE xx inconnu malgre la table : un token que BASEXT.ASM ne declare pas
    if "tokens inconnus" in r.stderr:
        erreur("sharpbasic %s :\n%s" % (args[0], r.stderr))
    return r.stdout


def compresser(exe, bas, bsa):
    sharpbasic(exe, "compress", bas, "-o", bsa, "--input-encoding", "cp437")


def decompresser(exe, bsa, bas):
    sharpbasic(exe, "decompress", bsa, "-o", bas, "--output-encoding", "cp437")


def annoncer(mots, bsa):
    """les mots-cles de BASEXT effectivement TOKENISES, comptes dans le .BSA : un
       nom cite dans un REM ou une chaine n'y figure pas, et ne doit pas y figurer"""
    vus = []
    for m, t in sorted(mots.items(), key=lambda kv: kv[1]):
        n = bsa.count(bytes([0xFE, t]))
        if n:
            vus.append("%s x%d" % (m, n) if n > 1 else m)
    print("tokens  : %s" % (" ".join(vus) if vus else "aucun mot-cle de BASEXT"))


def main():
    args = sys.argv[1:]
    mots = mots_de_basext()
    print("%d mots-cles lus dans src/BASEXT.ASM" % len(mots))
    ecrire_table(mots)
    if args == ["--table"]:
        return
    if not args or args[0].startswith("-"):
        erreur("usage : bsa_basext.py <fichier.BAS|.BSA> [-o <sortie>]\n"
               "        bsa_basext.py --table      (la table seule)\n"
               "        le sens est deduit du fichier : un .BSA commence par FFh")

    exe = trouver_sharpbasic()
    print("outil   : %s" % exe)

    src = os.path.abspath(args[0])
    # le sens se deduit du fichier, pas de son nom : un .BSA commence par FFh et
    # porte 34h en octet 4 (Format-BASIC-tokenise-PC-E500S.md §1)
    brut = open(src, "rb").read()
    vers_le_bas = len(brut) >= 5 and brut[0] == 0xFF and brut[4] == 0x34
    if "-o" in args:
        sortie = os.path.abspath(args[args.index("-o") + 1])
    else:
        sortie = os.path.splitext(src)[0] + (".BAS" if vers_le_bas else ".BSA")
    if os.path.abspath(sortie) == src:
        erreur("la sortie ecraserait la source")

    if not vers_le_bas and brut.count(b"\n") != brut.count(b"\r\n"):
        erreur("le .BAS doit etre en CRLF (voir MODE-EMPLOI §9.3)")

    with tempfile.TemporaryDirectory(prefix="bsa_basext_") as tmp:
        if vers_le_bas:
            annoncer(mots, brut)
            decompresser(exe, src, sortie)
            # le .BAS obtenu, repasse a l'aller, doit redonner le .BSA de depart
            controle = os.path.join(tmp, "controle.BSA")
            compresser(exe, sortie, controle)
            if open(controle, "rb").read() != brut:
                erreur("le .BAS obtenu ne redonne pas le .BSA de depart")
            print("\nverifie : recompresse, le .BAS redonne le .BSA de depart, octet pour octet")
            print("ecrit   : %s (%d lignes)" % (sortie, open(sortie, "rb").read().count(b"\r\n")))
            return

        compresser(exe, src, sortie)
        final = open(sortie, "rb").read()
        annoncer(mots, final)
        # aller-retour binaire : decompresse puis recompresse, les memes octets.
        # ⚠️ On ne compare PAS le listing relu au .BAS de depart : la mise en forme
        #    canonique rend « ERN ; » la ou l'on ecrit « ERN; » -- un ecart d'AFFICHAGE
        #    sans rapport avec les octets. On le montre, sans le reprocher.
        relu, refait = os.path.join(tmp, "relu.BAS"), os.path.join(tmp, "refait.BSA")
        decompresser(exe, sortie, relu)
        compresser(exe, relu, refait)
        if open(refait, "rb").read() != final:
            erreur("aller-retour binaire : la recompression ne redonne pas les memes octets")
        for n, (a, b) in enumerate(zip(brut.split(b"\r\n"), open(relu, "rb").read().split(b"\r\n")), 1):
            if a != b:
                print("   mise en forme, ligne %d : [%s] rendu [%s]"
                      % (n, a.decode("cp437"), b.decode("cp437")))

    taille = int.from_bytes(final[7:9], "little")
    print("\nverifie : aller-retour binaire -- decompresse puis recompresse,")
    print("          les memes octets reviennent")
    print("ecrit   : %s (%d octets ; en-tete : taille+33 = %d)" % (sortie, len(final), taille))
    if taille != len(final) + 33:
        erreur("en-tete incoherent")


if __name__ == "__main__":
    main()
