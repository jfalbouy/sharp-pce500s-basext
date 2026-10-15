#!/usr/bin/env python3
r"""bsa_basext.py -- produit le .BSA d'un programme qui emploie les mots-cles de BASEXT.

    python C:\Claude\BASEXT\outils\bsa_basext.py ..\essais\DWGLTEST.BAS

⛔ POURQUOI CET OUTIL EXISTE. « Sharp Basic Converter » tokenise les 168 mots-cles
   de la ROM, et eux seuls : mesure du 2026-10-15, il laisse DWGL, XCONSOLE, XCLS
   et SREPT$ EN CLAIR dans le .BSA. Un tel fichier ne marche pas sur la machine --
   l'interpreteur y lirait des noms de variables. C'etait le point ouvert n. 10 du
   MODE-EMPLOI, et la reponse est donc : non, il ne les accepte pas.

✅ CE QU'IL SAIT FAIRE, LUI. Le convertisseur reste employe tel quel -- il a ete
   verifie identique A L'OCTET au .BSA produit par le Sharp lui-meme (DRVTEST.BSA,
   1131 octets, pointeurs de saut compris). On ne touche donc pas a sa sortie : on
   lui donne, a la place de chaque mot-cle de BASEXT, un mot-cle de la ROM ABSENT
   du programme -- une DOUBLURE --, puis on remplace dans le .BSA l'octet de token
   de la doublure par celui de BASEXT.

   La doublure et le mot-cle vrai pesant tous deux « FEh + 1 octet », AUCUNE
   longueur ne change : ni celle des lignes, ni les POINTEURS DE SAUT, qui valent
   « offset dans le fichier + 33 » (Format-BASIC-tokenise-PC-E500S.md §3). C'est
   toute l'astuce, et c'est ce qui rend l'operation sure.

   La substitution de texte ne touche ni l'interieur des chaines, ni ce qui suit
   un REM : « 10 REM DWGLTEST ... » doit rester tel quel.

   Le resultat est VERIFIE par aller-retour : on repose les doublures dans le .BSA
   produit, on le decompresse, on redonne leurs noms aux mots-cles, et on compare
   au .BAS de depart. Octet pour octet.
"""
import os
import re
import subprocess
import sys

SHARPBASIC = r"C:\Claude\Sharp Basic Converter\Publish\sharpbasic.exe"

# les mots-cles de BASEXT et leur token (src/BASEXT.ASM)
BASEXT = {
    "LPEEK": 0x07, "WPEEK": 0x0A, "LPOKE": 0x0E, "MOD": 0x0F,
    "INSTR": 0xC2, "TRIM$": 0xC3, "LTRIM$": 0xC4, "RTRIM$": 0xC5,
    "UCASE$": 0xC6, "LCASE$": 0xC7, "REPT$": 0xC8, "SREPT$": 0xC9,
    "XCONSOLE": 0xCA, "XCLS": 0xCF, "DWGL": 0xD3,
}

CSV = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "..", "donnees", "tokens-rom83.csv")


def doublures_possibles():
    """les FONCTIONS de la ROM, lues dans la table generee. Pourquoi des
       fonctions : une doublure ne doit JAMAIS introduire une reference de ligne
       (GOTO, THEN, ELSE...), que le convertisseur resout en POINTEUR -- cela
       changerait la longueur. Aucune fonction n'en introduit."""
    pool = []
    for ligne in open(CSV, encoding="utf-8").read().split("\n")[1:]:
        ch = ligne.split(",")
        if len(ch) < 3 or ch[2] != "fonction":
            continue
        nom, code = ch[1], int(ch[0], 16)
        if re.fullmatch(r"[A-Z]+\$?", nom):
            pool.append((nom, code))
    return pool


def erreur(m):
    print("ERREUR : " + m)
    sys.exit(1)


def mots_presents(texte, mots):
    """les mots de la liste qui apparaissent dans le texte, bornes de mot"""
    vus = []
    for m in mots:
        if re.search(r"(?<![A-Z0-9$])" + re.escape(m) + r"(?![A-Z0-9$])", texte):
            vus.append(m)
    return vus


def substituer(texte, table):
    """remplace les cles de la table par leur valeur, HORS chaines et HORS REM.
       table : {nom -> remplacement}. Plus long d'abord (XCONSOLE avant XCLS)."""
    noms = sorted(table, key=len, reverse=True)
    sortie = []
    for ligne in texte.split("\r\n"):
        i, n, hors = 0, len(ligne), []
        chaine = False
        while i < n:
            c = ligne[i]
            if c == '"':
                chaine = not chaine
                hors.append(c)
                i += 1
                continue
            if not chaine:
                # REM : tout le reste de la ligne est litteral
                if ligne.startswith("REM", i) and (i == 0 or not ligne[i - 1].isalnum()):
                    hors.append(ligne[i:])
                    break
                pris = None
                for m in noms:
                    if ligne.startswith(m, i):
                        apres = ligne[i + len(m):i + len(m) + 1]
                        avant = ligne[i - 1:i]
                        if not (apres and (apres.isalnum() or apres == "$")) and \
                           not (avant and (avant.isalnum() or avant == "$")):
                            pris = m
                            break
                if pris:
                    hors.append(table[pris])
                    i += len(pris)
                    continue
            hors.append(c)
            i += 1
        sortie.append("".join(hors))
    return "\r\n".join(sortie)


def compresser(bas, bsa):
    r = subprocess.run([SHARPBASIC, "compress", bas, "-o", bsa, "-f"],
                       capture_output=True, text=True, errors="replace")
    if r.returncode or not os.path.exists(bsa):
        erreur("sharpbasic compress :\n" + r.stdout + r.stderr)


def decompresser(bsa, bas):
    r = subprocess.run([SHARPBASIC, "decompress", bsa, "-o", bas, "-f"],
                       capture_output=True, text=True, errors="replace")
    if r.returncode or not os.path.exists(bas):
        erreur("sharpbasic decompress :\n" + r.stdout + r.stderr)


def echanger_tokens(octets, paires):
    """remplace les FE <a> par FE <b> ; rend aussi le compte par paire"""
    out = bytearray(octets)
    compte = {}
    i = 0
    while i < len(out) - 1:
        if out[i] == 0xFE:
            for a, b in paires:
                if out[i + 1] == a:
                    out[i + 1] = b
                    compte[(a, b)] = compte.get((a, b), 0) + 1
                    break
            i += 2
        else:
            i += 1
    return bytes(out), compte


def main():
    if len(sys.argv) < 2:
        erreur("usage : bsa_basext.py <fichier.BAS> [-o <sortie.BSA>]")
    src = os.path.abspath(sys.argv[1])
    sortie = None
    if "-o" in sys.argv:
        sortie = os.path.abspath(sys.argv[sys.argv.index("-o") + 1])
    else:
        sortie = os.path.splitext(src)[0] + ".BSA"

    texte = open(src, "rb").read().decode("ascii")
    if texte.count("\n") != texte.count("\r\n"):
        erreur("le .BAS doit etre en CRLF (voir MODE-EMPLOI §9.3)")

    # quels mots-cles de BASEXT le programme emploie-t-il ?
    employes = mots_presents(texte, BASEXT)
    if not employes:
        print("aucun mot-cle de BASEXT : sharpbasic suffit, rien a faire ici")
    # une doublure par mot-cle, et elle doit etre ABSENTE du programme
    libres = [(d, t) for d, t in doublures_possibles()
              if not mots_presents(texte, [d]) and d not in BASEXT]
    if len(libres) < len(employes):
        erreur("pas assez de doublures absentes du programme")
    couples = list(zip(sorted(employes, key=len, reverse=True), libres))

    print("mots-cles de BASEXT employes, et leur doublure :")
    for mot, (dbl, tdbl) in couples:
        print("   %-9s FE %02X   <-  %-10s FE %02X" % (mot, BASEXT[mot], dbl, tdbl))

    tmp = os.path.join(os.environ.get("TEMP", "."), "_bsa_basext")
    os.makedirs(tmp, exist_ok=True)
    doublé = os.path.join(tmp, os.path.basename(src))
    open(doublé, "wb").write(
        substituer(texte, {m: d for m, (d, _) in couples}).encode("ascii"))

    inter = os.path.join(tmp, "inter.BSA")
    compresser(doublé, inter)
    brut = open(inter, "rb").read()

    # les noms de BASEXT ne doivent plus trainer en clair HORS des REM :
    # on ne peut pas le verifier simplement, l'aller-retour ci-dessous le fera.
    final, compte = echanger_tokens(brut, [(t, BASEXT[m]) for m, (_, t) in couples])
    for mot, (dbl, tdbl) in couples:
        n = compte.get((tdbl, BASEXT[mot]), 0)
        if n == 0:
            erreur("la doublure %s n'a produit aucun token : %s n'a pas ete tokenise"
                   % (dbl, mot))
        print("   %-9s : %d token(s) remis en place" % (mot, n))

    # --- verification par aller-retour -------------------------------------
    retour, _ = echanger_tokens(final, [(BASEXT[m], t) for m, (_, t) in couples])
    if retour != brut:
        erreur("l'echange de tokens n'est pas reversible")
    rt = os.path.join(tmp, "retour.BSA")
    open(rt, "wb").write(retour)
    rtbas = os.path.join(tmp, "retour.BAS")
    decompresser(rt, rtbas)
    # ⚠️ on NE compare PAS le listing relu au .BAS de depart : le convertisseur a
    #    sa mise en forme canonique (il rend « ERN ; » la ou l'on ecrit « ERN; »),
    #    et cet ecart d'AFFICHAGE n'a rien a voir avec les octets. On recompresse
    #    donc, et on exige l'identite BINAIRE.
    rtbsa = os.path.join(tmp, "retour2.BSA")
    compresser(rtbas, rtbsa)
    if open(rtbsa, "rb").read() != brut:
        erreur("aller-retour binaire : la recompression ne redonne pas les memes octets")
    relu = open(rtbas, "rb").read().decode("ascii")
    rendu = substituer(relu, {d: m for m, (d, _) in couples})
    ecarts = [(i + 1, a, b) for i, (a, b) in
              enumerate(zip(texte.split("\r\n"), rendu.split("\r\n"))) if a != b]
    for n, a, b in ecarts:
        print("   mise en forme, ligne %d : [%s] rendu [%s]" % (n, a, b))

    open(sortie, "wb").write(final)
    taille = int.from_bytes(final[7:9], "little")
    print("\nverifie : aller-retour binaire -- decompresse puis recompresse,")
    print("          les memes octets reviennent")
    print("ecrit   : %s (%d octets ; en-tete : taille+33 = %d)" % (sortie, len(final), taille))
    if taille != len(final) + 33:
        erreur("en-tete incoherent")


if __name__ == "__main__":
    main()
