# DWGL — une instruction BASIC pour la barre de menu (IOCS 58h)

*Rédigé le 2026-10-14 — mis à jour le 2026-10-14*

Étude de faisabilité d'un mot-clé BASEXT qui trace la **barre de cases** du Sharp — celle de la
touche `MENU` et des libellés de touches de fonction — depuis un programme BASIC, sans `POKE` ni
zone langage machine réservée.

> **Légende**, celle de `MODE-EMPLOI.md` : ✅ confirmé (mesuré sur machine) · 📖 lu dans la ROM ou
> dans une documentation, pas éprouvé · ⚠️ piège ou point incertain · ⛔ erreur corrigée, gardée
> écrite avec ce qui l'a démentie.
>
> **Aucun code n'est écrit à ce stade.** Ce document dit ce qui est acquis, ce qui est mesuré, ce
> qui reste à trancher, et ce que coûterait l'écriture.

---

## 1. Verdict

**Faisable, et sans inconnue de fonctionnement.** L'appel lui-même est déjà éprouvé sur PC-E500S
réel par deux voies, et la machine fournit le modèle complet d'un menu à plus de cinq choix. Ce qui
reste est de l'écriture : lire quatre arguments, bâtir un tampon, appeler.

| Acquis | Où | État |
|---|---|---|
| paramètres de la commande `58h` | `Referentiel PC-E500S SC62015/04-fcs-iocs.md` §2.4ter, lus en `0F2C90h` | ✅ mesuré le 2026-10-10 |
| appel depuis un simple `CALL` BASIC | `Referentiel PC-E500S SC62015/Documentation/GUIDE.ASM`, 60 octets | ✅ PC-E500S réel, 2026-10-12 |
| même appel piloté depuis le BASIC | `*MNU` de `ROUTINES/ROUTINES/ROUTINES.BAS` | ✅ PC-E500S réel, 2026-10-11 |
| mécanique d'ajout d'un mot-clé | `MODE-EMPLOI.md` | 14 mots-clés en service |

Ce que DWGL apporte par rapport à `*MNU` : ni zone langage machine à réserver, ni 26 octets
`POKE`és, ni repli en `LOCATE`/`PRINT` — et, avec BASEXT-DRV, un mot-clé disponible en permanence.

---

## 2. Ce que la commande `58h` sait faire

| Entrée | Rôle |
|---|---|
| `(bl)`, `(bh)` | colonne et ligne de la première case |
| `A` | nombre de cases |
| `B` bit 0 | `0` crochets (glyphes `B7h`/`B8h`), `1` parenthèses (`C2h`/`C3h`) |
| `B` bit 7 | `0` efface d'abord la ligne `(bh)`, `1` la garde |
| `X` | les libellés, chacun terminé par `FFh` ; un `FEh` en tête est sauté |

✅ **Six caractères par case, toujours** (`mv il,006h` en `0F2CB5h`), complétés par des espaces, le
reste ignoré — le manuel technique p. 41 en annonce sept, à tort. Une case occupe donc **8 colonnes**
et cinq cases remplissent exactement la ligne de 40.

⛔ **Pas de repli de ligne.** L'écriture d'un caractère refuse si la colonne atteint 40 ou la ligne
4 (`cmp (bl),028h`, `cmp (bh),004h` en `0F23C3h`, puis `sc`/`retf`). Un appel de dix cases
tracerait les cinq premières et **perdrait les autres en silence** : il faut deux appels.

📖 La routine encadre son tracé de `SUB_F2526`/`SUB_F253F`, qui sauvent et rendent `[(iocsw)+9]` :
elle paraît donc gérer le curseur elle-même. Non mesuré.

📖 Le guide finit sur `retf` **sans fixer la retenue** : l'appelant doit faire `rc`, comme
`fkey_display` en `0F1D3Eh`.

---

## 3. Le modèle de la machine : l'écran `MENU`

C'est la pièce qui manquait, et elle répond à la question « plus de cinq choix ».

| Élément | Ce que fait la ROM |
|---|---|
| libellés page 1 | `0F92AFh` : `BASIC ` `FF` ` CAL  ` `FF` `MATRIX` `FF` ` STAT ` `FF` ` ENG  ` `FF` |
| libellés page 2 | `0F92D2h` : ` AER  ` `FF` ` CARD ` `FF` — **1 ou 2 cases**, la seconde seulement si le fichier `CARD    BAS` existe (`SUB_F9712` en `0F9A45h`) |
| drapeau de page | un octet de travail, inversé à chaque tracé par `xor (003h),0FFh` (`0F9A59h`) |
| changement de page | touche de code **`0Eh`** (`chg`), testée en `0F9AFEh` : elle relance le tracé |
| tracé | `A = 5` cases (ou 1-2 en page 2), `(bl),(bh) = 0,3`, commande `58h` (`0F9A69h`) |
| choix | codes **`013h`-`017h` = `PF1`-`PF5`** → `sub a,013h` donne 0-4, **et `add a,005h` en page 2** (`0F9A95h`) → 5-9 |
| titre en vidéo inverse | `or [lcd_mode],040h` avant d'écrire, remis après (`0F9AB7h`/`0F9AD0h`) |

⛔ **La machine ne cherche jamais à savoir « sur quelle ligne de menu on est », et n'emploie pas
`2ndF`.** Elle garde un drapeau de page, le bascule sur une touche, retrace les cinq mêmes cases, et
**ajoute 5 à l'indice**. Les touches `PF6`-`PF10` n'existent pas dans ce dialogue.

### Le petit marqueur à gauche

📖 Ce n'est ni un caractère, ni un curseur mobile, ni une sortie de la `58h` : c'est un **motif
graphique de 4 octets** (`0A 1B 1B 0A`, en `0E229Dh`) posé par `SUB_E2285` (`(si) = 1`, `(di) = 18`,
`dotsop = 1`) juste après le tracé de la barre (`0F9A6Eh`). Il revient **au même endroit** à chaque
rafraîchissement, quelle que soit la case choisie : c'est un indicateur, pas un pointeur de
sélection. La même routine sert à deux autres écrans système (`0E1142h`, `0E1A0Ch`).

Un programme peut le reproduire par `GCURSOR` + `GPRINT`, ou par la commande `4Ah` de l'affichage.

### L'autre jeu de libellés, celui des touches de fonction

Même mécanique, ailleurs : `fkey_display` (clavier `46h`, `0F1CFAh`) lit le sélecteur `0BFC40h`
(`0` → libellés en `013h`, sinon en `033h` du fichier `FUNCKEY`, deux jeux distants de 32 octets),
le passe **tel quel en `B`** à la `58h` — d'où des **parenthèses** pour le second jeu — et pose le
bit 0 de `0BFC3Fh` (« la barre est affichée »). La bascule est en `0F2FB8h` (`xor [0BFC40h],001h`),
sur la même touche `0Eh`.

✅ **Le changement crochets → parenthèses est donc la façon dont la machine signale « second jeu ».**
C'est reproductible par le seul bit 0 de `tag`.

---

## 4. Les touches, mesurées le 2026-10-14 (PC-E500S, `ROUTINES/MEMCHK/KEYCODE.BAS`)

| Lecture | `PF1` | `2ndF`+`PF1` | `PF5` | `2ndF`+`PF5` |
|---|---|---|---|---|
| `INKEY$ &1` | `F1h` | **`F1h`** | `F5h` | **`F5h`** |
| `INPUT$ (1)` | `52 55 4E 20` = `RUN ` | `52 55 4E 20` | `… 4F 41 44 20` = `… OAD ` | `55 52 4E 20` = `… URN ` |

✅ **`INKEY$ &1` ne distingue pas `2ndF`** : `PF1` et `2ndF`+`PF1` rendent le même `F1h`.
✅ **`INPUT$ (1)` ne rend pas un code de touche mais le texte programmé de la touche**, et celui-ci
change avec `2ndF` : `LOAD ` contre `RETURN ` (seules les fins sont visibles, les premières lignes
ayant défilé). Cohérent avec le relevé du 2026-10-10, où `CTRL`+`PF4` donnait `00h` puis `56h`.

**Conséquence** : pour un menu, c'est `INKEY$ &1` qu'il faut — il rend `F1h`-`F5h`, propres et sans
texte parasite. Le second jeu de cinq choix se gère donc **comme la ROM le fait** : un drapeau de
page dans le programme, une touche pour le basculer, et 5 ajoutés à l'indice. Il n'y a rien à
détecter.

---

## 5. Spécification proposée

```basic
DWGL colonne, ligne, tag, chaine$
```

| Argument | Domaine | Rôle |
|---|---|---|
| `colonne` | 0-39 | colonne de la première case ; `colonne + 8 × cases ≤ 40` |
| `ligne` | 0-3 | ligne de la barre |
| `tag` | 0-255 | le registre `B` : **bit 0** parenthèses au lieu de crochets, **bit 7** garder le reste de la ligne (sinon la ligne est effacée). Les autres bits sont ignorés par la ROM |
| `chaine$` | 1 à 5 libellés séparés par des virgules | chaque libellé est tronqué ou complété à six caractères |

⛔ **Pas de paramètre « nombre de caractères » :** la largeur est figée à six par la ROM (§2). Et
pas de paramètre « nombre de cases » : il se déduit des virgules, comme dans `*MNU`.

**Dix choix** : deux appels, soit sur deux lignes, soit sur la même ligne en alternant par un drapeau
de page — exactement le modèle du §3.

```basic
10 P=0
20 IF P=0 THEN DWGL 0,3,0,"BASIC,DUMPM,DRIVER,TRDOS,SUITE"
30 IF P=1 THEN DWGL 0,3,1,"UUENC,RENUM,HIST,REGIS,RETOUR"
40 K$=INKEY$ &1:IF K$="" THEN 40
50 N=ASC K$-&F0:IF N<1 OR N>5 THEN 40
60 IF N=5 THEN P=1-P:GOTO 20
70 PRINT "CHOIX ";N+5*P:END
```

**Refus proposés**, dans l'esprit des autres mots-clés (`MODE-EMPLOI.md` §6.6) :

| Cas | Erreur |
|---|---|
| `colonne`, `ligne` hors domaine, plus de 5 libellés, barre qui déborde de la ligne | 33 — *Data out of range* |
| `chaine$` vide, ou argument de mauvais type | 90 — *Type mismatch* |
| ponctuation attendue absente | 10 — *Syntax error* |

---

## 6. Implantation : ce qu'elle coûte

**Où** : dans `BASEXT.ASM`, donc servi d'un coup par le module autonome et par le pilote résident
BASEXT-DRV (une seule source, deux objets — `BASEXT-DRV/README.md`).

| Point | État |
|---|---|
| **Place** | ⚠️ le module autonome occupe **2709 octets sur 3072**, soit **363 libres**. DWGL demande son code **plus un tampon** de libellés (5 cases × 7 + 1 = 36 octets suffisent pour une barre). C'est jouable, mais c'est la contrainte dimensionnante : le pilote, lui, a de la place |
| **Quatre arguments** | BASEXT n'est jamais allé au-delà de trois (`INSTR`). C'est le point ouvert n° 8 du mode d'emploi, avec le chemin repéré (`MID$`, `0FD75Ah`) : trois `eval` numériques puis un `eval` chaîne, ponctuation lue à la main (§5.3) |
| **Token** | à prendre dans les 86 libres (§2.3) ; `DWGL` ne commence par aucun mot-clé existant et n'est le début d'aucun — règle du §1.2 |
| **Relogeable** | ⚠️ tout ajout doit rester mesurable par `BASEXT-DRV/outils/reloc.py`, et ne **jamais** tester une plage d'adresses — c'est le piège qui avait mordu `xf_on`/`xf_off` |
| **Appel** | `(bl)`, `(bh)`, `A`, `B`, `X` puis `mvw (cl),00000h` / `mv il,058h` / `callf iocs_call` / `rc` — les octets de la ROM, déjà vérifiés identiques entre `0F1D29h`, `GUIDE.OBJ` et les `POKE` de `*MNU` |

### Trois pièges à traiter dans le code

1. ⚠️ **Écran à 4 lignes.** L'appel direct ne refait aucun des trois contrôles de `fkey_display`.
   Sur un écran de 4 lignes, la barre écrase du texte. DWGL doit lire `lcd_height` (`0BFC9Eh`) et
   refuser, ou l'assumer et le documenter.
2. ⚠️ **`XCONSOLE` ne confine pas cette barre** : son filtre est branché sur le handle 0 du FCS, la
   `58h` passe par l'IOCS. Une barre tracée dans une fenêtre `XCONSOLE` en sortira.
3. ⚠️ **Le débordement est silencieux** côté ROM (§2) : c'est à DWGL de refuser, pas à l'appelant de
   s'en apercevoir.

---

## 7. Points ouverts

| # | Question | Pour la trancher |
|---|---|---|
| 1 | Le tampon de libellés : dans le module, ou réemploi de `xf_buf` (240 octets, au filtre de `XCONSOLE`) ? | décider ; le réemploi économise 36 octets mais lie deux mots-clés |
| 2 | DWGL doit-elle tracer aussi le marqueur graphique du §3 ? | essai visuel |
| 3 | Le comportement exact au-delà de la colonne 40 (cases perdues, et dans quel état laisse-t-il la ligne) | essai : `*MNU` avec **six** libellés |
| 4 | La `58h` déplace-t-elle le curseur du BASIC ? | essai : `LOCATE` connu, `DWGL`, puis `PRINT` |
| 5 | Le texte programmé des touches gêne-t-il un menu ? `INKEY$ &1` l'évite, mais un appui malencontreux sur `ENTER` le délivrerait | essai, ou documentation d'emploi |

---

## 8. Sources

- `Referentiel PC-E500S SC62015/04-fcs-iocs.md` §2.4ter et §2.4quater — la `58h`, son unique
  émetteur dans la ROM, `GUIDE.ASM`, les deux bits d'état et le sélecteur `0BFC40h`.
- `ROUTINES/ROUTINES/README.md` §4.9 et `ROUTINES.BAS` lignes 50850-50875 — `*MNU`, éprouvée.
- `rom83.bin`, désassemblée par `e500dasm` : `0F2C90h` (la commande), `0F23B4h` (l'écriture d'un
  caractère et ses refus), `0F9AA6h`-`0F9B15h` (l'écran `MENU`), `0F9A41h`-`0F9AA5h` (tracé, pages,
  touches), `0F1CFAh`-`0F1D3Eh` (`fkey_display`), `0F2FB1h` (la bascule de jeu), `0E2285h` (le
  marqueur), `0F92AFh`/`0F92D2h`/`0F9293h` (les libellés et le titre).
- Mesures sur PC-E500S réel : `GUIDE.OBJ` (2026-10-12), `*MNU` (2026-10-11), `KEYCODE.BAS`
  (2026-10-10 et **2026-10-14**, J.-F. Albouy).
- `MODE-EMPLOI.md` — §1.2 nommage, §2.3 tokens libres, §5 lecture des arguments, §6.6 erreurs,
  §9 mise en œuvre, §12 points ouverts.
