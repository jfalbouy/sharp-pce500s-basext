# BASEXT — étendre le BASIC du PC-E500S

*Rédigé le 2026-09-15 — mis à jour le 2026-09-16*

Ajouter à l'interpréteur BASIC du **PC-E500S** ses propres **instructions** et **fonctions**, qui
s'emploient ensuite exactement comme celles de la ROM : `PRINT LPEEK &BF100`, `A$=TRIM$ (B$)`,
`LPOKE &BF800,&12345`. Ce ne sont pas des `CALL` déguisés, mais des mots-clés du langage.

## Un projet transverse, et le référent

Ce dossier rassemble **la connaissance sur la création de nouvelles instructions BASIC**,
indépendamment des outils qui la servent. **Il est le référent** : les autres projets de
`C:\Claude` renvoient ici, et une correction se fait ici d'abord. Chacun des outils y contribue
sans en être le propriétaire :

| Projet | Rôle pour BASEXT |
|---|---|
| `xasm2026-4` | assemble le module (`.OBJ`, `.lst`, `.UU`) |
| `SC62015Disassembler` (`e500dasm`) | lit la ROM : tables, résolveurs, services, et vérifie l'objet |
| `Sharp transfert serial` | porte le `.UU` sur la machine |
| `Sharp Basic Converter` | `.BAS` ⇄ `.BSA` |
| `Referentiel PC-E500S SC62015` | le chapitre historique, `12-extensions-basic.md` |

## Par où commencer

| Document | Pour |
|---|---|
| **[`MODE-EMPLOI.md`](MODE-EMPLOI.md)** | **créer une instruction** : le référentiel des 168 instructions standard (codes, nature, adresses), la procédure, les adresses de la ROM, la restitution à l'interpréteur, les gabarits, les pièges |
| [`JOURNAL-MISE-AU-POINT.md`](JOURNAL-MISE-AU-POINT.md) | l'histoire de la mise au point : chaque défaut, sa cause et la mesure qui l'a tranché |
| `Referentiel PC-E500S SC62015/12-extensions-basic.md` | le référentiel d'origine : cadres, device 9, matrices, méthode |

## Le module : quatorze mots-clés

✅ Les douze premiers validés sur émulateur PC-E500S le 2026-09-15. ✅ `XCONSOLE` et `XCLS`
éprouvés par J.-F. Albouy avec `essais/XCONTEST.BAS` : fenêtres, `XCLS` qui épargne les lignes
figées, retour à 4 lignes, et les cinq refus (33, 33, 33, 90, 10).
✅ Le **filtre d'écriture** qui confine le défilement quand `début` > 0 est éprouvé par
J.-F. Albouy avec `essais/XSCROLL.BAS` : ligne haute figée pendant le défilement, haut et bas figés
avec retour à la ligne automatique, puis retour à 4 lignes.
✅ `essais/BEXTTEST.BAS` passe les 14 mots-clés (`*** 14/14 OK ***`, 2026-09-16).
`BASEXT.ASM` fait 2709 octets, en `0BF000h`–`0BFA94h`.

⚠️ **`CLS` dans une fenêtre de moins de 4 lignes affiche les libellés des touches de fonction**
sur la ligne 3 : c'est la ROM (`CLS` appelle `fkey_display` quand `lcd_height` ≠ 4, `0F931Ah` →
`0F1CFAh`). Dans une fenêtre, effacer par `XCLS` ; pour tout effacer, `XCONSOLE : CLS`.

⛔ **Les essais qui écrivent en mémoire visent `&BFBF0`**, au-delà de la fin du module. `&BF800`
et `&BF300`, libres autrefois, sont aujourd'hui **dans** le module : `BEXTTEST.BAS` y écrasait le
filtre et faisait perdre ses lecteurs à la machine (`MODE-EMPLOI.md` §10).

| Mot-clé | Token | Genre | |
|---|---|---|---|
| `LPEEK adr` | `07h` | fonction | valeur de 3 octets |
| `WPEEK adr` | `0Ah` | fonction | valeur de 2 octets |
| `LPOKE dest,v1,v2,...` | `0Eh` | **instruction** | écrit chaque valeur sur 3 octets |
| `MOD (a,b)` | `0Fh` | fonction | reste entier, de 0 à 1 048 575 |
| `INSTR ([début,] t$,r$)` | `C2h` | fonction | position de `r$` dans `t$`, 0 si absente |
| `TRIM$ (s$)` | `C3h` | fonction chaîne | sans espaces de début ni de fin |
| `LTRIM$ (s$)` | `C4h` | fonction chaîne | sans espaces de début |
| `RTRIM$ (s$)` | `C5h` | fonction chaîne | sans espaces de fin |
| `UCASE$ (s$)` | `C6h` | fonction chaîne | en majuscules |
| `LCASE$ (s$)` | `C7h` | fonction chaîne | en minuscules |
| `REPT$ (n,c$)` | `C8h` | fonction chaîne | `n` fois le 1er caractère de `c$` |
| `SREPT$ (n,s$)` | `C9h` | fonction chaîne | `n` fois `s$`, résultat ≤ 255 |
| `XCONSOLE [début][,[n]]` | `CAh` | **instruction** | borne la console aux lignes `début`..`début+n−1` : écrit `lcd_height` et, si `début` > 0, branche un filtre d'écriture sur le handle 0 ; `XCONSOLE` seul rétablit l'écran et le débranche |
| `XCLS` | `CFh` | **instruction** | efface la fenêtre de `XCONSOLE`, curseur en `(0,début)` |

## Arborescence

```
BASEXT/
├── README.md                  ce fichier
├── MODE-EMPLOI.md             le mode d'emploi et référentiel
├── JOURNAL-MISE-AU-POINT.md   le journal de mise au point
├── src/
│   ├── BASEXT.ASM             le module (14 mots-cles) -- + .OBJ .lst .UU
│   ├── STREXT.ASM             module de developpement des 8 fonctions chaine -- + .obj .lst .uu
│   ├── LSEPT.ASM              l'ancetre : la seule fonction LPEEK -- + .OBJ .lst .UU
│   └── pce500.inc             constantes systeme, GENEREES (ne pas editer a la main)
├── essais/
│   ├── BEXTTEST.BAS           les 14 mots-cles (XCONSOLE et XCLS ajoutes le 2026-09-16)
│   ├── XCONTEST.BAS           XCONSOLE et XCLS : trois fenetres, puis les cinq refus
│   ├── XSCROLL.BAS            defilement confine : ligne haute figee, puis haut et bas figes
│   ├── BEXT.BAS               LPEEK et LPOKE, litteraux puis variables
│   ├── TEST.BAS               WPEEK, valeur nulle, borne des 20 bits
│   ├── MODTEST.BAS            MOD confronte au BASIC sur 40 valeurs
│   ├── MODDIAG*.BAS           diagnostics de MOD (temoins de cadre)
│   └── RESULT.TXT             un vidage releve sur machine
├── outils/
│   └── extraire_tokens.py     lit la table des tokens dans rom83.bin
└── donnees/
    ├── tokens-rom83.csv       la table generee (168 mots-cles)
    └── tokens-rom83.md        la meme, en Markdown (reprise dans MODE-EMPLOI §2.4)
```

## Démarrage rapide

**Assembler** (depuis `src/`, pour que `include pce500.inc` se résolve) :

```powershell
cd C:\Claude\BASEXT\src
C:\Claude\xasm2026-4\bin\xasm2026-4.exe BASEXT.ASM -O -L -S -B -K
```

**Sur la machine**, dans cet ordre (`MODE-EMPLOI.md` §9) :

```basic
POKE &BFE03,&1A,&FD,&B,0,&C,0 : CALL &FFFD8   ' reserver 3072 octets (petit reset)
LOAD M "S1:BASEXT.OBJ" : CALL &BF000          ' charger et installer
W=LPEEK &BFD0E : PRINT HEX$ LPEEK (W+&90)     ' verifier : BF8E7 pour cette version
```

**Puis seulement** charger le programme qui emploie les mots-clés : le BASIC tokenise à la saisie.

**Régénérer la table des tokens** :

```powershell
python C:\Claude\BASEXT\outils\extraire_tokens.py
```

## Règles de maintenance

- **Une adresse se vérifie dans la ROM ou dans le `.lst`, jamais de mémoire.** Les adresses du
  module changent à chaque assemblage.
- **`pce500.inc` est généré** (`xasm2026-4/tools/generate_pce500_inc.py`, depuis les carnets du
  désassembleur) : le corriger à la source, puis recopier.
- **La table des tokens se régénère**, elle ne s'édite pas.
- **Fichiers `.BAS` destinés à la machine** : CRLF et MAJUSCULES ASCII.
- **Tout ajout de mot-clé** : vérifier le nom et le token (`MODE-EMPLOI.md` §2), puis mettre à jour
  le tableau ci-dessus, `BEXTTEST.BAS` et le journal.
- **`src/BASEXT.ASM` est aussi inclus par `C:\Claude\BASEXT-DRV`**, qui en fait un pilote
  résident de `S1:` (2026-09-16). Le pilote pose `def basext_pilote`, ce qui masque l'include de
  `pce500.inc`, l'`org` et le `pre_on` du module. Tout ajout doit donc rester **relogeable** : pas
  d'octet qui dépende de l'adresse hors d'un champ de 2 ou 3 octets, pas d'`assert` sur une adresse
  absolue. Après modification, relancer
  `python C:\Claude\BASEXT-DRV\outils\reloc.py BASEXT.ASM` depuis `src/` : il refuse ce que le
  pilote ne saurait pas reloger. ⚠️ Un test sur une **plage d'adresses** du module
  (`0BF000h`–`0BFFFFh`) lui échappe, car ce n'est pas un champ d'adresse : `xf_on`/`xf_off` en
  faisaient un, remplacé **sous `ifdef basext_pilote`** par une comparaison exacte à `xf_entry`
  (`xf_nous`, 2026-09-16) ; le module autonome garde le sien.

## Origine de ce dossier

Constitué le **2026-09-15** à partir de `SC62015Disassembler/Samples/BASEXT/`. Les sources, objets
et essais y ont été **copiés** et non déplacés ; le `README.md` d'origine est devenu
`JOURNAL-MISE-AU-POINT.md`. Vérifié à la copie : `BASEXT.ASM` et `STREXT.ASM`, réassemblés depuis
`src/`, redonnent des objets **identiques à l'octet** aux `.OBJ` copiés.

✅ **Le `README.md` de l'original est devenu un renvoi** vers ce dossier le 2026-09-15.
`BASEXT.ASM.bak`, la sauvegarde d'avant la fusion des fonctions chaîne, a été recopiée dans `src/`
et vérifiée identique.

✅ **Les 22 autres fichiers de `SC62015Disassembler/Samples/BASEXT/` ont été supprimés** le même
jour par J.-F. Albouy : il ne reste là-bas que le renvoi. Juste avant, chacun avait été vérifié
par empreinte contre sa copie d'ici. 19 étaient identiques ; les 3 autres étaient plus anciens
que leur copie : `BEXTTEST.BAS` (ligne 60), `STREXT.ASM` (en-tête corrigé) et `STREXT.lst`
(réassemblé, l'objet inchangé). Dans le dépôt git du désassembleur, la suppression n'est pas
encore commitée.

Les documents des autres projets qui citaient `Samples/BASEXT` ou `Samples/LPEEK` renvoient
désormais ici : le référentiel (`00-index`, `03`, `05`, `06`, `07`, `12-extensions-basic`), le
désassembleur (`BASIC-en-ROM.md`, `Routines-ROM-PC-E500S.asm`,
`SC62015_InstructionSet_Reference.md`), le rapport de bug de `xasm2026-4` et la skill `pc-e500s`.
⚠️ Les commentaires des sondes `Samples/DEVICE9/*.ASM` citent encore `Samples/BASEXT` : ce sont
des relevés de mesure datés, et les modifier désynchroniserait leurs `.lst`.

## Corrections reportées dans les autres projets (2026-09-15)

- **Pas de `pmdf` pour rendre une chaîne lue par `eval`** (`MODE-EMPLOI.md` §6.1) :
  `12-extensions-basic.md` et l'en-tête de `src/STREXT.ASM`.
- **86 tokens libres, et non 88** (§2.3) : `12-extensions-basic.md`, `Routines-ROM-PC-E500S.asm`.
- **Le retour d'une chaîne est établi** : `12-extensions-basic.md` le donnait encore pour ouvert.

## Points ouverts

Les neuf points ouverts du mécanisme : `MODE-EMPLOI.md` §12.
