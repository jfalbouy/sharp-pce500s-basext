# DWGL — une instruction BASIC pour la barre de menu (IOCS 58h)

*Rédigé le 2026-10-14 — mis à jour le 2026-10-18*

Étude de faisabilité d'un mot-clé BASEXT qui trace la **barre de cases** du Sharp — celle de la
touche `MENU` et des libellés de touches de fonction — depuis un programme BASIC, sans `POKE` ni
zone langage machine réservée.

> **Légende**, celle de `MODE-EMPLOI.md` : ✅ confirmé (mesuré sur machine) · 📖 lu dans la ROM ou
> dans une documentation, pas éprouvé · ⚠️ piège ou point incertain · ⛔ erreur corrigée, gardée
> écrite avec ce qui l'a démentie.
>
> ⛔ **Ce document a été écrit avant le code, et le code existe depuis.** `DWGL` est écrit le même
> jour dans `src/BASEXT.ASM` et dans le pilote `BASEXT-DRV` 0.3 : voir le **§8**, qui dit ce qui a
> été retenu, ce que les mesures ont tranché et ce qui reste à éprouver sur machine. Les §§1 à 8
> restent l'étude telle qu'elle a été faite.

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
| mécanique d'ajout d'un mot-clé | `MODE-EMPLOI.md` | 14 mots-clés en service, `DWGL` est le 15ᵉ |

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

📖 **Un libellé plus court que six caractères est complété par des espaces par la ROM elle-même**
(`LOC_F2CE1` : `mv a,020h` répété `IL` fois), et un libellé plus long est **tronqué** — elle saute
jusqu'au `FFh` suivant (`LOC_F2CCF`). Lu dans `0F2CB5h`-`0F2CEFh` le 2026-10-14. Conséquence pour
l'écriture : il n'y a **ni à compléter ni à tronquer**, seulement à poser un `FFh` à la place de
chaque virgule.

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
| changement de page | touche **`↕`**, code **`0Eh`** testé en `0F9AFEh` : elle relance le tracé — voir la correction ci-dessous |
| tracé | `A = 5` cases (ou 1-2 en page 2), `(bl),(bh) = 0,3`, commande `58h` (`0F9A69h`) |
| choix | codes **`013h`-`017h` = `PF1`-`PF5`** → `sub a,013h` donne 0-4, **et `add a,005h` en page 2** (`0F9A95h`) → 5-9 |
| titre en vidéo inverse | `or [lcd_mode],040h` avant d'écrire, remis après (`0F9AB7h`/`0F9AD0h`) |

⛔ **La machine ne cherche jamais à savoir « sur quelle ligne de menu on est », et n'emploie pas
`2ndF`.** Elle garde un drapeau de page, le bascule sur **`↕`**, retrace les cinq mêmes cases, et
**ajoute 5 à l'indice**. Les touches `PF6`-`PF10` n'existent pas dans ce dialogue.

### ⛔ Les touches du MENU : j'avais lu la bonne adresse dans la mauvaise table

✅ **Mesuré sur PC-E500S le 2026-10-14 par J.-F. Albouy** : dans l'écran `MENU`, **les flèches ne
font rien**. Seule **`↕`** change de page ; `MENU` remonte à la racine, `BASIC` sort vers l'éditeur ;
`PF1`-`PF5` choisissent ; **toutes les autres touches sont inertes**.

⛔ **Ce document disait « touche `0Eh` (`chg`) », en comprenant `0Eh` comme la flèche droite. C'était
faux**, et l'erreur tient en une phrase : la boucle du MENU (`0F9AE8h`) lit par l'IOCS **`43h`
`key_read`**, donc par les **tables du pilote — celles que voit `INPUT$`** —, et non par celle
d'`INKEY$` (`0F9C5Dh`), où `0Eh` est bien la flèche droite. **Le MENU lit le clavier comme
`INPUT$`, pas comme `INKEY$`** : c'est toute l'explication. Lues dans la bonne table, les quatre lignes du MENU disent exactement ce que
la machine fait :

| Ce que fait la boucle | Pourquoi |
|---|---|
| `cmp a,000h` / `jrnz` : **ne retient que les codes à DEUX octets** dont le premier est `00h` | `A` = premier octet, `B` = second |
| les flèches sont **rejetées** | leur code est à **un** octet (`1Ch`-`1Fh`, table `0307A4h`) : `A ≠ 0`, la boucle reboucle |
| `B = 0Eh` → change de page | dans la table à deux octets du pilote `030806h` — **la table d'`INPUT$`** —, l'indice `0Eh` vaut `0Eh` : c'est le **code matriciel de `↕`**, et `INPUT$ (1)` le rendrait en deux lectures, `00h` puis `0Eh` |
| `B = 0Fh` ou `04h` → `LOC_F9B14` : `sc` puis retour | les deux sorties, **retenue armée** ; l'appelant les distingue — ce sont `MENU` et `BASIC`, non départagées ici |
| `B = 13h`-`17h` → `sub a,013h` | `PF1`-`PF5`, identité dans la même table |

**La ROM prédit donc la mesure**, une fois lue au bon endroit. Et la table `030806h` est l'identité
sur ces indices, ce qui rendait la confusion facile : `0Eh` y est un **code matriciel**, pas un
caractère.

📖 **Conséquence pour un menu en BASIC**, et elle tombe sur le partage du §4 : la ROM lit `↕` par
la voie d'`INPUT$` (deux octets, `00h` puis `0Eh`), qui est **bloquante** et qui rend le **texte
programmé** des `PF`. `INKEY$`, lui, rend proprement `F1h`-`F5h` mais consulte **sa** table
(`0F9C5Dh`), où le même code matriciel `0Eh` vaut **`1Eh`**.

Donc, en théorie, `INKEY$ &1` devrait rendre **`1Eh`** sous `↕` — et un menu tiendrait avec cette
seule fonction. ⚠️ **Déduit de la table, non mesuré**, et je viens justement de payer une
déduction de table : un appui avec `ROUTINES/MEMCHK/KEYCODE.BAS` le dit. Si `INKEY$` ne rendait
rien, il faudrait les **deux** fonctions, comme l'annonce `04-fcs-iocs.md` §2.4ter.
À relever aussi : l'indice `0Fh` de la table d'`INKEY$` vaut `00h`, donc **l'une des deux touches
de sortie du MENU est invisible à `INKEY$`**.

### Le petit marqueur à gauche

📖 Ce n'est ni un caractère, ni un curseur mobile, ni une sortie de la `58h` : c'est un **motif
graphique de 4 octets** (`0A 1B 1B 0A`, en `0E229Dh`) posé par `SUB_E2285` (`(si) = 1`, `(di) = 18`,
`dotsop = 1`) juste après le tracé de la barre (`0F9A6Eh`). Il revient **au même endroit** à chaque
rafraîchissement, quelle que soit la case choisie : c'est un indicateur, pas un pointeur de
sélection. La même routine sert à deux autres écrans système (`0E1142h`, `0E1A0Ch`).

✅ **Un programme le repose en UNE ligne de BASIC**, et l'arithmétique est lue dans la ROM, pas
devinée :

```basic
GCURSOR (1,25):GPRINT "0A1B1B0A"      ' AVANT de tracer la barre
```

**L'ordre compte**, et c'est le seul piège : voir deux paragraphes plus bas.

| Ce qu'il fallait savoir | Où c'est lu |
|---|---|
| `GCURSOR (x,y)` prend `y` au **bas** de la colonne de 8 points | `GPRINT` passe `y − 7` à la commande `4Ah` : `mv y,0FFFFF9h` / `add y,i` en `0FD3D7h` |
| d'où **25** pour le sommet 18 de la ROM | `18 + 7` |
| `GPRINT` met lui-même `dotsop` à **0** | `and [dotsop],000h` en `0FD350h` — la ROM, elle, emploie `1` pour le marqueur ; les deux s'affichent |
| `x` avance d'un point par octet | `inc i` en `0FD3CBh` |

**En général**, pour une barre tracée en (`colonne`, `ligne`) :
`GCURSOR (6 × colonne + 1, 8 × ligne + 1)` — 6 points par colonne de caractère, et `8 × ligne + 1`
redonne 25 pour la ligne 3.

✅ **Fidèle au point près, vérifié deux fois** : en comparant les deux clichés (l'écran `MENU` de
la machine et notre tracé, mêmes 816 × 186 pixels), puis **sur le Sharp réel le 2026-10-15**, qui
donne le même résultat que l'émulateur. Les lignes de points sombres sont les **mêmes dans les
deux images** :

| | marqueur | barre |
|---|---|---|
| écran `MENU` | 114, 118, (vide), 126, 130 | 138 à 164 |
| `GCURSOR (1,25):GPRINT` | 114, 118, (vide), 126, 130 | 138 à 164 |

Soit, en points d'écran : fenêtre de huit points de 18 à 25, allumés en **18, 19, 21, 22** — le
bit de poids faible est bien le point du **haut** —, puis **une seule ligne de points vide**
(23) avant le haut du crochet (24). ⚠️ **Ce voisinage serré n'est pas un défaut de notre ligne :
c'est l'espacement de la machine elle-même.**

⛔ **Le motif n'est pas « décalé de deux points » : il est déjà calé en haut de l'octet.** Le
dessin tient sur les points **0 à 4** de la colonne de huit, les points 5, 6 et 7 étant vides :

```
0Ah 1Bh 1Bh 0Ah        point 0 : .##.      point 4 : .##.
                       point 1 : ####      point 5 : ....
                       point 2 : ....      point 6 : ....
                       point 3 : ####      point 7 : ....
```

⛔ **Et j'ai tiré de là une conclusion fausse, que la machine a démentie.** Voyant le marqueur
« empiéter » sur le crochet, j'ai cru à un espacement trop serré de la ROM et retenu `23`. ✅ **La
mesure de J.-F. Albouy, le 2026-10-18, dit autre chose : `25` est la bonne valeur, et le défaut
venait de l'ORDRE des instructions.**

**La cause**, et elle est dans les trois points vides du bas : `GPRINT` met `dotsop` à **0**
(`and [dotsop],000h` en `0FD350h`) et écrit la colonne de huit points **entière, bits à zéro
compris** — il **remplace**, il n'ajoute pas. Tracé *après* la barre, le marqueur **efface** donc
les deux premières lignes de points du crochet (24 et 25).

✅ **Vérifié dans les clichés**, colonne du crochet seule (x 0-22 px, trois captures du même
écran) :

| | lignes de pixels du crochet |
|---|---|
| écran `MENU` de la ROM | 138, 142, 146, 150, 154, 158, 162 |
| marqueur tracé **après** la barre | **—, —,** 146, 150, 154, 158, 162 |
| marqueur tracé **avant** la barre | 138, 142, 146, 150, 154, 158, 162 — **identique à la ROM** |

✅ **La règle, donc** : `GCURSOR (6 × colonne + 1, 8 × ligne + 1)` — soit `(1,25)` pour la ligne 3 —
**et le tracer AVANT la barre**. `DWGL` refait ensuite la ligne entière, et comme il n'efface que
*sa* ligne, le marqueur de la ligne au-dessus survit. Au changement de page, il suffit de retracer
la barre : inutile de reposer le marqueur.

✅ **Les trois modes de `dotsop`, lus dans la commande `4Ah` elle-même (2026-10-18).** La table
des commandes du pilote d'écran est en `0F2224h`, indexée par `commande − 3Fh` sur deux octets :
`4Ah` mène à **`0F80F9h`**. Le mode y est appliqué par un combinateur de dix instructions,
`0F81EFh` :

```asm
        mv   a,[dotsop]
        cmp  a,001H          ; le mode ; mv ne touche pas aux indicateurs
        mv   a,(cl)          ; A = l'octet DEJA A L'ECRAN
        jrc  LOC_F8200       ; dotsop = 0
        jrz  LOC_F8203       ; dotsop = 1
        xor  a,(0DEH)        ; dotsop >= 2 : OU EXCLUSIF
        ret
LOC_F8200:
        and  a,(di)          ; masque : ne garde que ce qui est HORS fenetre
LOC_F8203:
        or   a,(0DEH)        ; puis ajoute les points du motif
        ret
```

| `dotsop` | opération | effet |
|---|---|---|
| **0** | `(écran ET masque) OU motif` | **remplacement** — les points à **0 du motif EFFACENT** |
| **1** | `écran OU motif` | **ajout** — n'efface jamais rien |
| **≥ 2** | `écran OU EXCLUSIF motif` | **inversion** |

✅ **Et tout se referme** : `GPRINT` force le mode **0** (`0FD350h`), d'où l'effacement mesuré des
deux lignes du crochet ; la ROM emploie le mode **1** pour son marqueur (`0E22BBh`), d'où son droit
de le poser **après** la barre sans rien abîmer. Le code prédit la mesure, et la mesure confirme le
code.

⚠️ **Le carnet reste à corriger à sa source** : `pce500.inc` annote `4Ah` « 0 allumer, 1 éteindre,
2 inverser ». « 1 éteindre » est faux — c'est un OU, il ne peut rien éteindre. L'annotation vient
vraisemblablement de la commande **`4Ch`** (`display_dot_write`, un point isolé), dont le manuel
décrit le paramètre `A` ainsi ; or `4Ch` **range précisément `A` dans `dotsop`** (`0F7E14h`), donc
les deux commandes partagent la variable. 📖 Pour un point isolé, « allumer » coïncide avec le
remplacement, mais « éteindre » ne coïncide pas avec le OU : le chemin du point isolé prépare
peut-être d'autres opérandes, ce que je n'ai pas suivi.

⚠️ Sans conséquence pour un programme BASIC : `GPRINT` force le mode `0` à chaque appel, on ne peut
pas lui en demander un autre. La règle reste donc : **tracer le marqueur avant la barre**.

⛔ **Et c'est pourquoi le marqueur N'EST PAS dans `DWGL`.** Il y tenait en option (`tag` bit 1, les
bits 1 à 6 étant ignorés par la ROM), mais le code pèse **~90 octets** — quatre appels `4Ah`, le
calcul des deux coordonnées, la sauvegarde de `X` et `Y` autour de chaque appel — et le module
autonome n'a plus que **61 octets** libres. Il aurait fallu soit le réserver au pilote (deux objets
au comportement différent, ce que la source unique interdit par principe), soit descendre l'`org`
du module et perdre `CALL &BF000`. Une ligne de BASIC coûte **zéro octet** et laisse le placement
libre : le marqueur n'est pas une sortie de la `58h`, il n'a pas à être dans le mot-clé.

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

## 8. Ce qui a été écrit, le 2026-10-14

`DWGL` existe. Elle est dans `src/BASEXT.ASM`, donc dans **les deux objets** : le module autonome
et le pilote résident — le pilote étant celui qui l'intéresse, puisqu'une barre de menu n'a de
valeur que disponible en permanence.

### 8.1 La signature retenue

```basic
DWGL colonne, ligne, tag, chaine$
```

Celle du §5, sans changement : trois nombres de 0 à 255, puis une chaîne dont les **virgules**
séparent les libellés. `NbCaracteres` n'existe pas (la ROM fige six caractères), le nombre de
cases se déduit des virgules.

| Refus | Erreur |
|---|---|
| `ligne` ≥ 4 | 33 |
| plus de cinq libellés | 33 |
| `colonne + 8 × cases` > 40 | 33 |
| `chaine$` de plus de **47** caractères (la taille du tampon) | 33 |
| l'argument n'est pas une chaîne, ou la chaîne est vide | 90 |
| une virgule manque entre deux arguments | 10 |

### 8.2 Les points ouverts du §7, tranchés

| # | Ce qui a été fait |
|---|---|
| 1 | **Tampon propre au mot-clé**, `dw_buf`, **48 octets** — et non le réemploi de `xf_buf`. Les 48 octets économisés n'auraient pas suffi à faire tenir le bloc (il manquait 57 octets), et lier `DWGL` au filtre de `XCONSOLE` pour rien n'avait pas de sens |
| 2 | **Non, et la mesure confirme le choix** : `DWGL` ne trace pas le marqueur. Une ligne de BASIC le fait — `GCURSOR (1,25):GPRINT "0A1B1B0A"`, arithmétique lue dans la ROM (§3) — quand l'option dans le mot-clé coûtait ~90 octets pour 61 libres |
| 3 | **Sans objet** : `DWGL` refuse elle-même avant d'appeler (erreur 33), là où la ROM perdait les cases en silence. L'essai « `*MNU` avec six libellés » reste à faire pour la curiosité, plus pour la sûreté |
| 4 | ✅ **Clos** : la `58h` ne déplace pas le curseur du BASIC — le `PRINT` qui suit tombe où il doit (essai du 2026-10-14) |
| 5 | ✅ **Clos** : le texte programmé des touches ne gêne pas, puisque `INKEY$ &1` ne le voit jamais. Mesuré le 2026-10-15 : la touche haut-bas y rend `1Eh`, les `PF` `F1h`-`F5h` ; `INPUT$`, lui, rendrait le texte |

### 8.3 Ce que l'écriture a appris

- ⛔ **La ROM complète et tronque elle-même** (§2, lu le même jour) : le code n'a ni à aligner sur
  six caractères ni à couper. Le tampon ne fait que remplacer chaque `,` par un `FFh` et poser un
  `FFh` final.
- ✅ **Quatre arguments ne posent aucune difficulté** — c'était le point ouvert n° 8 du
  `MODE-EMPLOI.md`, qui renvoyait à `MID$`. Il n'a pas fallu le lire : il suffit de rendre `BP`
  **en absolu** après chaque argument. Le gabarit est désormais au §8.5 du mode d'emploi, et le
  point est clos.
- ⚠️ **La chaîne se lit à `U`**, comme le fait `INSTR` (éprouvé), et non par `(BP+1)`, qui n'a été
  vérifié sur aucun chemin.
- ⛔ **Et `mv x,u` écrase le point de reprise du BASIC.** C'est le seul vrai défaut de l'écriture,
  et il n'a pas été vu à la relecture : il a été **trouvé en exécutant le code**. `X` revenait à
  l'interpréteur avec l'adresse de la pile `U`. `INSTR` l'évitait déjà par `pushs x`/`pops x`
  (`0BF599h`) ; `DWGL` fait désormais de même.
- ⚠️ **Un refus après la lecture de la chaîne doit rendre `U`**, pas seulement `BP` : sans cela,
  un `ON ERROR` dans une boucle ferait descendre `U` d'autant à chaque passage. Seul le refus de
  longueur est concerné (une chaîne vide n'occupe rien, un argument qui n'est pas une chaîne n'a
  rien empilé).
- ⚠️ **Le bloc du pilote a débordé** : 3129 octets pour 3072 de place sous l'installateur de
  `0BF000h`. Le chargement est descendu de `0BE400h` à **`0BE000h`** et la réservation de 6144 à
  **7168** octets (`BASEXT-DRV/CONCEPTION.md` §5quater). Le module autonome, lui, tient encore :
  2999 octets sur 3072, **73 libres**.
- ⚠️ **`CLS` efface la barre et la remplace** par les libellés `FUNCKEY` dès que l'écran n'est pas
  à 4 lignes (`0F931Ah`) : dans une fenêtre, effacer par `XCLS`. C'est le piège déjà connu de
  `XCONSOLE`, et il tombe exactement sur l'emploi de `DWGL`.

### 8.4 Ce qui reste

✅ **Exécutée sur PC, dans les deux objets.** `essais/DWGLEMU.py` interprète les octets assemblés
dans un SC62015 réduit, avec `eval`, `dec2bin` et `iocs_call` simulés selon leur contrat
(`MODE-EMPLOI.md` §5 et §7.1), et vérifie à chaque cas la retenue, le code d'erreur, `BP`, `U`,
`S`, `X`, les paramètres passés à la `58h` et le contenu du tampon. Une vingtaine de cas passent
**dans le module autonome** et **dans le bloc du pilote relogé en `080018h`** par sa propre table
de relocation. C'est ce banc qui a trouvé le défaut de `mv x,u`.

✅ **ÉPROUVÉE SUR PC-E500S RÉEL le 2026-10-14** — `essais/DWGLTEST.BAS`, relevé photographique de
J.-F. Albouy. Les six écrans sont conformes, sans exception :

| Étape | Écran | Ce qu'elle établit |
|---|---|---|
| 1 | `[BASIC ][DUMPM ][DRIVER][TRDOS ][SUITE ]` | cinq cases de huit colonnes, ligne 3, crochets |
| 3 | `[A     ][TROPLO][C     ]` | ✅ **la ROM complète à six caractères et tronque elle-même** — ce n'était que lu (`LOC_F2CE1`/`LOC_F2CCF`), c'est désormais mesuré |
| 4 | `[UN    ][DEUX  ](MILIEU)(DROITE)` | ✅ **bit 7** : le second appel garde les cases du premier ; ✅ **bit 0** : parenthèses. Deux barres sur une même ligne |
| 5 | `33 33 33 90 90 33 10` | ✅ les **sept refus**, dans l'ordre et au code près |
| 6 | `(UUENC )(RENUM )(HIST  )(REGIS )(RETOUR)` puis `CHOIX 1` | ✅ le menu à dix choix : `INKEY$ &1`, drapeau de page, `PF5` bascule, indice `N+5*P` |

### Les touches, mesurées le 2026-10-15

✅ **J.-F. Albouy, `KEYCODE.BAS` sur PC-E500S** — la touche qui tourne les pages du MENU, celle du
double pictogramme sous `TITLE` :

| | `INKEY$ &1` | `INPUT$ (1)` |
|---|---|---|
| la touche **haut-bas** du MENU | **`1Eh`** | **`00h`** puis **`0Eh`** |
| l'autre touche à double flèche (large, à gauche de `PF1`) | — | `00h` puis `8Ah` |

✅ **Les deux voies concordent avec les tables, et la prédiction était juste** : le code matriciel
est `0Eh`, la table d'`INKEY$` (`0F9C5Dh`) y porte `1Eh`, et la table à deux octets du pilote
(`030806h`, celle d'`INPUT$`) y porte `0Eh` derrière le préfixe `00h` — exactement ce que la boucle
du MENU teste. La seconde touche a le code matriciel **`5Ah`** (`030806h` y porte `8Ah`) : ce n'est
pas celle du MENU.

**Conséquence, et elle est bonne** : `INKEY$ &1` suffit à un menu complet — `F1h`-`F5h` pour les
cinq choix, `1Eh` pour tourner la page. Pas besoin des deux fonctions. Un menu à **dix choix réels**
s'écrit donc comme celui de la machine, sans sacrifier `PF5` à « SUITE » : c'est ce que fait
désormais `essais/DWGLTEST.BAS`.

✅ **Point ouvert n° 4 clos par la même image** : la `58h` **ne déplace pas le curseur du
BASIC**. Aux étapes 3 et 4, le `PRINT` qui suit l'appel écrit en ligne 1, exactement où il
écrirait sans elle — ce que laissaient attendre les `SUB_F2526`/`SUB_F253F` qui encadrent le
tracé.

✅ **`XCONSOLE 0,3` + `XCLS` et `DWGL` s'accordent** : la ligne 3 reste à la barre pendant que le
texte s'écrit au-dessus, et `XCLS` n'y touche pas.

✅ **Et c'est le PILOTE qui tournait** : l'installateur a répondu `BASEXT-DRV 0.3 (BEXT:)` /
`Already installed.` / `Hooks: CALL &80DD7`, soit un bloc résident en `080D80h`. `DWGL` a donc
été éprouvée **là où elle a de l'intérêt** — résidente dans `S1:`, sans zone langage machine
réservée. ✅ La 0.3 du pilote est allée jusqu'au bout le même jour : `DRVTEST.BAS`, `BEXTTEST.BAS` en
`*** 15/15 OK ***`, et la désinstallation `CALL &BF000 "-U"` puis `SET`/`KILL`.

✅ **Et le 2026-10-18, `essais/DWGLTEST.BSA` — le fichier tokenisé produit sur le PC par
`outils/bsa_basext.py` — a été chargé et exécuté sur le Sharp sans réserve.** La chaîne est donc
complète de bout en bout : source `.ASM` unique → pilote résident → mot-clé → programme d'essai
tokenisé sur le PC → machine.

---

## 9. Sources

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
