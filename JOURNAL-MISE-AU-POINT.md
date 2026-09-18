# BASEXT — ajouter des instructions et des fonctions au BASIC

*Rédigé le 2026-09-04 — mis à jour le 2026-09-15*

> **Ce fichier est le journal de mise au point.** C'est le `README.md` de
> `SC62015Disassembler/Samples/BASEXT/`, copié tel quel le 2026-09-15 quand BASEXT est devenu un
> projet transverse (`C:\Claude\BASEXT`). Il est gardé pour son histoire. Pour **créer** une
> instruction, lire [`MODE-EMPLOI.md`](MODE-EMPLOI.md). Les chemins relatifs du texte sont ceux
> de son ancien emplacement.
>
> **Corrections relevées à la copie**, laissées en tête pour que le texte d'origine reste lisible :
>
> - ⛔ **« Le `pmdf (bp_ram),0F1h` de `LOC_FD6F9` est INDISPENSABLE »** (§ *Les fonctions chaine*) :
>   **faux en général**. `LOC_FD6F9` est la fin de `CHR$`, dont le lecteur a déjà rendu son cadre.
>   `LEFT$`, qui lit par `eval`, finit en `LOC_FD7D3` sans aucun `pmdf`, comme le `ret_str` validé
>   de ce module (`0BF219h`). Ce qui compte est le bilan : `BP` d'entrée − 15. Voir
>   `MODE-EMPLOI.md` §6.1.
> - ⚠️ **Deux paragraphes « `dec2bin` ne convertit que 20 bits » se contredisent** : l'un dit qu'il
>   **refuse** (erreur 33), l'autre qu'il **tronque en silence** en citant `0EFB8Bh`. Le code
>   tranche : `dec2bin` (`0EFAD4h`) **refuse** (`mv a,021h` en `0EFB16h`), et c'est **`bin2dec`**,
>   auquel appartient `0EFB8Bh`, qui tronque.
> - ⚠️ « `dec2bin` accumule dans `X`, **registre de 20 bits** » : la borne **mesurée** est bien
>   2²⁰ (`MOD (1048576,5)` → erreur 33), mais le manuel CPU donne `X` pour un registre de
>   **24 bits**. La mesure fait foi ; l'explication reste à établir.
> - ⚠️ Le tableau des fichiers dit `MODTEST.BAS` « **pas encore passé sur machine** » ; la section
>   ✅ du 2026-09-05, plus bas, le dément (`40 CONTROLES OK`).
> - ⚠️ L'exemple `LPOKE &BF200,&123456,&789ABC` emploie des valeurs au-delà de 20 bits, que la
>   machine refuse. Le paragraphe « `dec2bin` ne convertit que 20 bits — et cela MORD » le dit
>   lui-même. `essais/BEXTTEST.BAS` (ligne 60) reprenait les mêmes valeurs : ✅ l'erreur 33 a été
>   vérifiée sur émulateur et la ligne corrigée (`&12345,&6789A`) le 2026-09-15.
> - ✅ Le bug `cmp a,(n)` de `xasm2026-4` est **corrigé** depuis le 2026-09-15, avec un test négatif ;
>   le rapport est `../xasm2026-4/RAPPORT-BUG-cmp-a-parentheses.md`.
> - ⚠️ « 88 tokens libres » : **86**, car `38h` et `A6h` ont une routine sans avoir de nom
>   (`MODE-EMPLOI.md` §2.3).

Un module machine qui **greffe ses propres mots-cles** sur l'interpreteur du PC-E500S. Ce
n'est pas un `CALL` deguise : `LPEEK` s'ecrit dans une expression, `LPOKE` est une
instruction a part entiere.

**Douze mots-cles** : quatre numeriques (`LPEEK`, `WPEEK`, `LPOKE`, `MOD`) et **huit chaine**
(`UCASE$`, `LCASE$`, `TRIM$`, `LTRIM$`, `RTRIM$`, `REPT$`, `SREPT$`, `INSTR`) — tous valides sur
emulateur PC-E500S le 2026-09-15.

## Les fichiers

| | |
|---|---|
| `BASEXT.ASM` | le module complet, **1740 octets** en `0BF000h` (4 numeriques + 8 chaine) |
| `BASEXT.OBJ` / `.lst` | son objet XASM et son listing |
| `BASEXT.UU` | le programme BASIC auto-decodeur qui l'installe sur la machine (nom en MAJUSCULES, extension comprise : c'est celui que porte son enveloppe `begin 644 BASEXT.OBJ`, et celui que le Sharp attend) |
| `pce500.inc` | les constantes systeme, copiees pour que le dossier assemble seul |
| `STREXT.ASM` | le module de **developpement des fonctions chaine** (les 8, autonome) ; sa mise au point a etabli la convention chaine, puis il a ete fusionne dans `BASEXT.ASM` |
| `BEXTTEST.BAS` | le programme d'essai des **12 mots-cles**, valide sur emulateur (2026-09-15) |
| `BEXT.BAS` | l'essai historique des numeriques **valide sur emulateur** (J.-F. Albouy, 2026-09-04) |
| `TEST.BAS` | son complement : `WPEEK`, la valeur nulle, la borne des 20 bits |
| `MODTEST.BAS` | l'essai de `MOD`, **pas encore passe sur machine** |
| `LSEPT.*` | l'anctre a une seule fonction, conserve |

```
xasm2026-4 BASEXT.ASM -O -L -S -B -K
```

## Ce qu'il ajoute

| Mot-cle | Genre | |
|---|---|---|
| `LPEEK <adr>` | fonction | la valeur de **3 octets** rangee a cette adresse |
| `WPEEK <adr>` | fonction | la valeur de **2 octets** |
| `LPOKE <dest>,<v1>,<v2>,...` | **instruction** | ecrit chaque valeur sur **3 octets**, a la suite |
| `MOD (A,B)` | fonction | le reste de la division entiere de `A` par `B` — **parentheses obligatoires**, entiers de 0 a 1048575 |
| `UCASE$ (s$)` | fonction chaine | `s$` en MAJUSCULES |
| `LCASE$ (s$)` | fonction chaine | `s$` en minuscules |
| `TRIM$ (s$)` | fonction chaine | `s$` sans les espaces de debut ni de fin |
| `LTRIM$ (s$)` | fonction chaine | `s$` sans les espaces de **debut** |
| `RTRIM$ (s$)` | fonction chaine | `s$` sans les espaces de **fin** |
| `REPT$ (n,c$)` | fonction chaine | `n` copies du **1er caractere** de `c$` (`REPT$(5,"*")` -> `*****`) |
| `SREPT$ (n,s$)` | fonction chaine | `n` copies de la chaine **entiere** `s$` (`SREPT$(3,"AB")` -> `ABABAB`) ; resultat <= 255 |
| `INSTR ([debut,] t$,r$)` | fonction | position 1-based de `r$` dans `t$` (a partir de `debut`), **0 si absent** — rend un **nombre** |

```basic
PRINT "["+TRIM$ (" ab ")+"]"      [ab]
PRINT UCASE$ ("abc")+LCASE$ ("XYZ")   ABCxyz
PRINT SREPT$ (3,"AB")             ABABAB
PRINT INSTR ("HELLO WORLD","WORLD")   7
```

```basic
LPOKE &BF200,&123456,&789ABC     met 56 34 12 en &BF200, puis BC 9A 78 en &BF203
PRINT HEX$ LPEEK &BF200          123456
```

`LPOKE` comble un manque reel : ces pointeurs de trois octets se decomposaient jusqu'ici a la
main, cote BASIC —

```basic
AH=INT (AD/&10000):AM=INT ((AD-AH*&10000)/&100):AL=AD-AH*&10000-AM*&100
POKE dest,AL,AM,AH
```

### Les parentheses de `MOD` sont obligatoires

⛔ `PRINT MOD(17,5)` et `PRINT MOD 17,5` sont refuses : il faut `MOD (17,5)`. Ce n'est pas un
choix, c'est la convention de la machine, lue dans `SUB_FD5E7` — le lecteur d'arguments de
`POINT (x,y)`, qui exige **trois** caracteres : `(` en `0FD5ECh`, `,` en `0FD5F9h` et `)` en
`0FD60Ah`.

Une premiere version n'en verifiait qu'un : `chknum` recevait `(17,5)` tout entier et tentait
d'evaluer une expression parenthesee. `Syntax error` sur emulateur. La lecon est celle qui
revient : **regarder comment la ROM fait avant d'ecrire**, comme `LPOKE` avait ete calque sur
`BAS_POKE`.

### `MOD` travaille en entier, de 0 a 1048575

Meme domaine que `LPEEK` et `LPOKE` : **des entiers de 0 a 1048575**. C'est la contrepartie
assumee du choix ci-dessous, et la borne n'est pas arbitraire — `dec2bin` accumule dans `X`,
registre de **20 bits**, et refuse lui-meme au-dela (`add x,a` puis `jrc` en `0EFAFBh`, puis
erreur 33). C'est donc la ROM, et non nous, qui rend l'erreur sur un operande trop grand.

Un operande **negatif** est refuse (erreur 33). `dec2bin` en rend la valeur absolue en
laissant le signe dans le bit 3 de `(bp+0)` : l'ignorer rendrait un resultat faux **en
silence**, ce qui est pire qu'une erreur. `MOD (A,0)` rend l'erreur **21, Division by zero** —
le code que la ROM elle-meme emploie pour ce cas, lu en `0ECD67h`.

Le reste etant toujours inferieur a `B`, il tient toujours dans les 20 bits que `bin2dec` sait
reconvertir : le resultat est exact sur tout le domaine.

### ⛔ Pourquoi la bibliotheque flottante de la ROM n'est pas employee ICI

Deux versions ont tente de calculer `A - B * INT (A/B)` par les commandes du **device 9**, et
**les deux ont plante la machine** — `CLS` puis retour au MENU principal, sans message.

⛔ **MAIS LA ROUTE IOCS N'EST PAS EN CAUSE, ET J'AI EU TORT DE L'ECRIRE.** Ce README affirmait
que « la ROM n'ecrit jamais 9 dans `(cl)`, donc l'appel etait faux ». L'observation est vraie
— zero occurrence sur les 256 Ko — mais **l'inference est invalide** : la ROM n'a pas besoin
de l'IOCS pour atteindre son propre driver, elle l'appelle directement. L'IOCS est la porte du
code **utilisateur**, et elle fonctionne : `Samples/DEVICE9/SQR.ASM` calcule `√2` par
`mvw (cl),00009h` / `mv il,<commande>` / `callf iocs_call`, mis au point sur machine en dix
etapes le 2026-09-02 — **trois jours avant que je ne declare la route impraticable**.

Ce qui a reellement fait planter ma premiere tentative **n'est donc pas etabli**. L'en-tete de
`SQR.ASM` liste trois fautes d'emploi trouvees a l'essai, dont un candidat serieux : sous
`pre_on`, `(000H)` est une adresse **directe**, pas `(BP+0)` — les operandes partaient en RAM
interne 0-4 et le driver ne les voyait jamais.

> **La lecon vaut mieux que la fonction** : avant d'ouvrir un chantier, lire ce que le depot a
> deja fait. Un `git log` sur `Samples/DEVICE9` aurait epargne deux plantages et une conclusion
> fausse. Detail dans le referentiel, `12-extensions-basic.md` §13.

**Seconde version : une AUTRE route, et son contrat n'est pas etabli.** Elle court-circuitait
l'IOCS. La voie
existe bel et bien, et elle etait deja dans ce module — `LPEEK` appelle `dec2bin` et `bin2dec`
par un `callf` **direct**, et ce sont les commandes `07Eh` et `07Fh` du meme driver. Les
autres commandes ont les memes entrees, lues une a une dans la table de repartition de
`drv_function` (`0EF029h`) : `DB_EF078`, entrees de **2 octets**, index = commande − `041h`.

| commande | entree | |
|---|---|---|
| `047h` | `0ECBA9h` | `add` |
| `048h` | `0ECBB4h` | `sub` |
| `049h` | `0ECBBFh` | `mul` |
| `04Ah` | `0ECBD8h` | `div` |
| `056h` | `0EE4D5h` | `int` |

Ces cinq adresses sont **verifiees** : chacune a la forme `call <travail>` puis **`retf`**, et
c'est ce `retf` qui les rend appelables depuis la page `0B`. Le repartiteur fait d'ailleurs
son `popu x` **avant** son `ret` (`0EF05Ah`), donc les appeler directement est legitime.

⛔ **Ce que ces adresses ne disent pas, c'est le CONTRAT.** La ROM a **deux** diviseurs,
`SUB_ECCEA` et `SUB_ECD85`, et l'entree `04Ah` ne mene qu'au second. Or le seul appelant connu
de la ROM — l'evaluateur d'expression, en `0E8559h` — ecrit :

```
mv   i,0000Fh
exl  (000h),(00Fh)     ; il ECHANGE X et Y
call SUB_ECBDC         ; ... puis seulement divise
```

**Il echange les deux operandes avant de diviser**, ce que ne fait aucune des trois autres
operations. Le sens des operandes de la division n'est donc pas celui que j'avais suppose, et
au-dela de celui-la il reste des conventions que rien, dans la ROM lue, ne fixe.

**Ce qui reste vrai :** avoir verifie les adresses ne suffit pas. Une adresse juste appelee
selon un contrat suppose plante exactement comme une adresse fausse. Tant que le contrat n'est
pas etabli, on ne construit pas dessus — mais **la route IOCS, elle, EST etablie**, et c'est
par la qu'il faudra passer si l'on veut donner a `MOD` le domaine complet du BASIC.

### Ce que fait `MOD` a la place : sa propre division

`MOD` n'emploie donc **que** des primitives deja eprouvees sur la machine par `LPEEK` et
`LPOKE` — `chknum`, `dec2bin`, `bin2dec` — et fait la division lui-meme, en binaire, par
**restauration** : 24 tours, entierement en RAM interne, dans la queue inutilisee du cadre.

```
reste = 0
24 fois :
    A <<= 1, le bit sortant entre dans reste     (rol sur 3 + 3 octets)
    tmp = reste - B                              (sbcl, 3 octets)
    si pas d emprunt : reste = tmp
```

Le quotient est jete — `MOD` n'en veut pas. Il n'y a **plus un seul saut hors du module dont
le contrat ne soit pas verifie**, et deux points de detail l'ont ete aussi :

- ⛔ **`shl`, et surtout pas `rol`** : sur ce processeur `ROL`/`ROR` sont **circulaires dans
  l'octet** — la retenue recoit bien le bit sortant, mais ce bit revient aussi en bas du **meme**
  octet, et rien ne passe au suivant. Une premiere version decalait `A` avec six `rol` : chaque
  octet tournait sur lui-meme, le reste ne recevait jamais aucun bit, et `MOD` rendait **0 pour
  toutes les valeurs**. La ROM tranche dans les deux sens — elle **chaine `shr`** sur des octets
  consecutifs (`F5 12 F5 13 F5 14 F5 15 F5 16` en `0EEBB8h`, cinq octets ; seul un decalage *a
  travers* la retenue se chaine ainsi), et elle emploie `ror` la ou il faut **lire** les bits sans
  detruire l'octet (`bin2dec` : huit `ror (00Bh)` / `jrnc` par octet, `0EFBA3h`). 📄 Notre propre
  `SC62015_InstructionSet_Reference.md` decrivait les deux familles « via C », ce qui ne peut pas
  etre vrai des deux : corrige.
- ces decalages **ne consultent pas `I`** : `bin2dec` enchaine son `ror` alors que `IL` vaut encore
  4 d'un `dadl` precedent, et n'en fait tourner qu'un octet.
- les instructions **bloc** bouclent `I` fois, pas `I+1` : `mv il,00Fh` puis
  `mvl (000h),(00Fh)` recopie bien les **15** octets d'un cadre.

Verifie par simulation avant d'etre rendu : **30 009 cas** — les bornes plus 30 000 tirages
dans `0..1048575` — **aucun ecart** avec le modulo de reference.

### ⛔ Ne rien supposer de ce que `chknum` fait de `BP`

La premiere version binaire tenait pour acquis qu'un `chknum` **empile un cadre de 15 octets**,
donc qu'apres le second appel le premier operande se relisait en `(bp+16)..(bp+18)`. Je l'avais
deduit d'un enchainement de la ROM en `0ECBCAh` — `call chknum` suivi d'une operation qui lit
`X` en `(bp+0)` **et** `Y` en `(bp+15)`, ce qui n'a de sens que si le `chknum` a decale.

**C'etait une inference, pas une mesure. La machine l'a dementie :** `MOD` ne plantait plus,
mais rendait **0 pour toutes les valeurs**.

Ce zero-la est un temoin precis, et il vaut la peine de le lire :

- si `B` avait ete mal lu, `MOD (17,5)` aurait donne l'**erreur 21** — le controle `B = 0` est
  en amont du calcul. Pas d'erreur : **`B` etait juste** ;
- `0` quelle que soit la paire est la signature d'un **`A` perdu** — `0 mod B`, ou `B mod B`,
  les deux valent 0 pour tout `B`.

Donc `A` n'etait pas la ou je l'avais suppose. Et `dec2bin` n'y est pour rien : sa sortie
normale est `mv (001h),x` / `popu y` / `popu x` / `rc` / `ret` (`0EFB1Bh`) — **elle ne touche
pas a `BP`**.

### La question est rendue sans objet, plutot que tranchee

Deviner une troisieme fois la taille et le sens du cadre aurait ete deviner une troisieme
fois. `MOD` ne depend donc plus de la reponse :

- **le premier operande est mis a l'abri en RAM du module** (`sv_a`) des que `dec2bin` l'a
  converti — donc **avant** que le second `chknum` ne puisse rien ecraser ;
- **`BP` est sauve et restaure en absolu** (`sv_bp0` a l'entree, `sv_bp1` juste apres le
  premier `chknum`) au lieu d'etre rattrape par des `pmdf` comptes a la main.

Le module se comporte alors exactement comme `LPEEK`, qui lui **fonctionne** : resultat en
`(bp+0)..(bp+3)`, `BP` tel qu'il etait apres **le premier** `chknum`. Que `chknum` empile 15
octets, 8, ou rien du tout, le resultat est le meme.

⚠️ Les operandes internes de ces sauvegardes sont en adressage **absolu**, pas en `(BP+n)` :
`(bp_ram)` exige donc un octet **PRE**, le piege meme qui avait fait ecrire les crochets en
`[(00Eh)+090h]` au tout debut du module. Verifie dans l'objet — on y lit bien
`30 D8 EF F1 0B EC`, avec son `30` de tete, et non `D8 …`.

Meme principe pour les erreurs : **on ne compte pas les cadres, on restaure `BP`**. Rendre
l'etat d'avant l'appel est la politique de la ROM elle-meme (`0ECD63h` rend ce qu'il a pris
avant de signaler l'erreur 21), et une restauration **absolue** ne peut pas se tromper de
compte — pas meme apres un `dec2bin` en echec, qui a deja rendu le sien
(`LOC_ECB5C` : `sc` / `pmdf (bp_ram),00Fh` / `ret`).

## ✅ `MOD` valide sur machine, expressions comprises (2026-09-05)

```
TABLE BF1E5 ATTENDU BF1E5        le bon module est installe
ZONE LM BF000 TAILLE 3072        la zone langage machine le protege
MOD (A,B)  = 34      MOD (A+1,B)= 35      MOD (I*3571,997)= 163
A RECU 1BE6 (7142)   B RECU 3E5 (997)     RESTE A3 (163)
BP0 135 BP1 120 CADRE 15
```

Et `MODTEST` rend `34 35 44` puis **`40 CONTROLES OK`** : le BASIC lui-meme confronte `MOD` a
`I*3571-997*INT (I*3571/997)` sur quarante valeurs, **sans un ecart**. Le vidage montre par
ailleurs le module **intact en memoire** — 69 octets releves, 9 differences, toutes des
variables ecrites a l'execution.

⚠️ **`old_kw` et `old_disp` valent zero, et c'est voulu.** Le controle d'idempotence a
refuse de sauver des crochets qui pointaient deja sur une extension : mieux vaut zero, qui se
voit, qu'une valeur fausse en silence. Consequence : **la desinstallation n'est pas disponible
tant que le module n'a pas ete installe sur une machine dont les crochets sont encore ceux de
la ROM** — apres un reset, avant toute autre extension.

## Historique de la validation

## ✅ `MOD` valide sur machine (2026-09-05)

`MOD (17,5)` rend **2**. Le vidage memoire pris dans la foulee etablit, octet par octet, que le
reste du module se comporte comme prevu :

| | |
|---|---|
| `0BF1B0`–`0BF1DC` | **identiques a l'objet** — code et tables intacts en memoire |
| `sv_a` = `11 00 00` | l'operande `A` = **17**, tel que `dec2bin` l'a converti |
| `sv_bp0` = `96h` = 150 | `BP` a l'entree ; apres le premier `chknum` il vaut 135, **soit 15 de moins** |
| `0BF1E7` et au-dela | **le cadavre du module precedent**, pas du BASIC — voir ci-dessous |

⛔ **Et j'ai d'abord mal lu ces octets-la.** J'avais ecrit que « le BASIC commence juste apres
le module, la marge est nulle ». C'est faux : `0BF1E7` porte `0F F9 F0 4B`, soit l'entree `MOD`
d'une **`disp_table`** (jeton `0Fh`, adresse `0BF0F9h`, drapeau `4Bh`) — celle du module de
**503 octets**, dont la table etait en `0BF1DBh`. Suivent `96 87` (ses `sv_bp0`/`sv_bp1`) et ses
`old_kw`/`old_disp`. Tout `0BF1E7`–`0BF1F6` est donc **le cadavre de ma version precedente**,
laisse en place par le chargement de la nouvelle, plus courte.

Le texte BASIC tokenise (`2A 26 31 30 30 30 30 2B` = `*&10000+`, `FE A4` = `PEEK`) ne commence
qu'a `0BF1F7h`, et rien n'etablit qu'il soit **vivant** plutot que le reste d'un programme plus
ancien. **La vraie marge sous le BASIC reste donc a mesurer** — et l'outil existe deja :
`A_AREA.BAS` (J.-F. Albouy, version 4 du 2026-08-23, a la racine de `C:\Claude`).

La zone langage machine s'etend de **`[0BFD1Ah]`** (le pointeur `USRWRK`) jusqu'a **`0BFC00h`**,
ou commence la System Data Area. `A_AREA.BAS` la lit et l'affiche :

```basic
ADRSTR = PEEK &BFD1A+PEEK &BFD1B*&100+PEEK &BFD1C*&10000   ' le debut de la zone
' taille = &BFC00 - ADRSTR
```

et la redimensionne par le service de reservation `secure_work_call` :

```basic
POKE &BFE03,&1A,&FD,&B,TL,TM,TH : CALL &FFFD8
'          └ l'adresse DU POINTEUR   └ la taille voulue
```

⚠️ **Consequence directe pour ce module.** Il vit en `0BF000h` — l'adresse qu'emploient
`PLINK` et `PLINKC`, et que le referentiel recommande au-dela des 23 octets d'`USRWRK`. Pour
qu'il soit **protege**, il faut donc que la zone descende au moins jusqu'a `0BF000h`, soit une
taille d'au moins `0BFC00h - 0BF000h` = **`0C00h` = 3072 octets**. Le menu d'`A_AREA.BAS`
l'affiche des l'ouverture (`* [debut - BFC00] -> taille *`) : **le lire suffit a savoir**, sans
rien modifier.

### ⛔ ET C'EST TRANCHE : LA ZONE N'EST PAS RESERVEE. Le vidage du 2026-09-05 (16h30)

Le doute etait « ces octets sont-ils du BASIC vivant, ou le cadavre d'un module precedent ? ».
Un second vidage l'a leve, et sans appel :

```
0BF1E7h : 4D 59 41 44 52 20 3D 20 FE A4 26 42 46 44 31 43 2A 26
           M  Y  A  D  R     =     [FE] [A4=PEEK] &  B  F  D  1  C  *  &
```

**`MYADR = PEEK &BFD1C*&`** — une ligne BASIC **tokenisee** (`FE A4` est le jeton `PEEK`), que
J.-F. Albouy venait d'ecrire pour lire le pointeur `USRWRK`. Aucun de nos modules n'a jamais
contenu ces octets.

**Le module s'arrete a `0BF1E6h`. Le BASIC ecrit a l'octet SUIVANT.** La marge est donc
**nulle**, la zone n'est pas reservee, et le module ne survit que parce que le BASIC n'a pas
encore grandi d'un octet de plus. Ce n'etait pas de la robustesse, c'etait de la chance.

✅ **A faire avant toute autre chose** — `A_AREA.BAS`, option **(2) Fixe l'adresse**, valeur
**`&BF000`** : la zone langage machine descend alors jusqu'au module, qui devient intouchable, et
3072 octets deviennent disponibles au lieu de zero. Le menu doit ensuite afficher
`* [BF000 - BFC00] -> 3072 *`. Le petit reset de `CALL &FFFD8` impose de reinstaller
l'extension ensuite — puis de recharger le programme, dans cet ordre (voir le piege de
tokenisation plus bas).

⛔ **`&BFC00` EST UN PLAFOND, PAS UNE BASE.** La reservation faite avant ce vidage portait un
start a **`&BFE00`** — or la System Data Area occupe `0BFC00h`–`0BFFFFh`, et `A_AREA.BAS` porte
ce plafond en dur (`ADRSET=&BFC00`, ligne 60). La taille calculee vaut alors
`&BFC00 - &BFE00` = **−512**, et la zone ne couvre rien : tout ce qui est en dessous,
`0BF000h` compris, reste au BASIC. C'est exactement ce que le vidage montre.

La valeur a saisir est donc **plus BASSE** que `&BFC00`, et au plus egale a l'adresse du module :

| start saisi | taille obtenue | le module en `0BF000h` est… |
|---|---|---|
| `&BFE00` | −512 | **non protege** |
| `&BF000` | 3072 | **protege**, avec 3072 octets |

⚠️ `CALL &FFFD8` provoque un petit reset : l'extension est a reinstaller apres.

⚠️ **Le module a ete installe DEUX FOIS, et cela se voit** : `old_kw` porte `0BF1B1h` et
`old_disp` `0BF1CCh` — **nos propres tables**, et non celles de la ROM. La seconde installation a
sauve les crochets de la premiere. Sans consequence sur le fonctionnement, mais **la
desinstallation est perdue**. Un `CALL &BF000` n'est donc pas idempotent ; il le deviendrait en
refusant de sauver un crochet qui pointe deja dans le module.

## ⛔ Deux evaluateurs dans la ROM, et ils ne lisent pas la meme chose

| | | |
|---|---|---|
| `chknum` | `0EFBF3h` | **un TERME** : nombre, variable, appel de fonction, ou expression entre parentheses — mais il s'arrete au premier **operateur**. C'est ce qu'emploie `PEEK` (`0F5F9Ch`), d'ou `PEEK &BFD1C*&100` = `(PEEK &BFD1C)*&100` |
| `eval` | `0EF26Eh` | une **EXPRESSION COMPLETE**. C'est ce qu'emploie `POINT (x,y)`, via `SUB_F5F65` en `0F5F65h` — et la reconnaissance des operateurs `AND`/`OR`/`XOR` est cablee juste a cote, en `0EF2C5h`. Douze sites de la ROM l'appellent par `callf` |

⛔ `MOD` employait le premier. **Mesure sur machine : `MOD (17,5)` et `MOD (A,B)` passaient,
mais `MOD (A+1,B)` et `MOD (I*3571,997)` echouaient** — `chknum` lisait `A`, puis butait sur
le `+`. `MOD` emprunte sa syntaxe a `POINT` : il lui faut donc `eval`. `LPEEK` et `WPEEK`
gardent `chknum`, puisqu'ils sont calques sur `PEEK`.

⚠️ `eval` ne signale pas lui-meme le type : ses appelants de la ROM font le
`test (000h),080h` a sa suite (`0F5F6Bh`). `MOD` fait de meme et rend l'erreur 90,
*Type mismatch*, le code que `chknum` emploie pour ce cas (`0EFC04h`).

⚠️ **Et le cadre pousse par `eval` n'est PAS mesure.** Celui de `chknum` vaut 15 octets,
releve sur machine (`BP` 150 → 135) ; rien ne dit qu'`eval` fasse de meme. `MOD` ne le suppose
donc pas : il sauve `BP` **en absolu** avant et apres la premiere evaluation (`sv_bp0`,
`sv_bp1`) et restaure par la valeur, jamais par un `pmdf` compte a la main. Les deux octets
etant lisibles depuis le BASIC, l'ecart se mesurera au prochain essai.

## ✅ Les six refus, eprouves un par un (2026-09-05)

| saisie | reponse de la machine |
|---|---|
| `MOD (17,0)` | **Division by Zero** — erreur 21 |
| `MOD (-17,5)` | **Data out of range** — erreur 33 |
| `MOD (1048576,5)` | **Data out of range** — erreur 33 |
| `MOD 17,5` | **Syntax error** — erreur 10 |
| `MOD ("A",5)` | **Type mismatch** — erreur 90 |
| `MOD (ASC "A",5)` | **0** — et c'est juste : `ASC "A"` = 65, `65 MOD 5` = 0 |

Le dernier n'etait pas prevu au programme et il vaut mieux que les cinq autres : il montre
qu'un **appel de fonction** passe comme argument. C'est l'evaluateur d'expression qui fait son
office, et la preuve que le passage de `chknum` a `eval` etait le bon geste.

## Adresses de la version 530 octets (2026-09-05, temoins retires)

⚠️ **Elles bougent a chaque assemblage** : les relire dans `BASEXT.lst`, jamais de memoire.
Le programme qui ecrit `MODDIAG.BAS` **lit lui-meme `kw_table` dans le listing** — je l'y avais
recopiee de tete une fois, et j'avais ecrit `BF1D9` pour `BF1DB`.

| | | |
|---|---|---|
| `kw_table` | `0BF1DBh` | ce que doit rendre le controle d'installation |
| `sv_a` | `0BF207h` | l'operande `A`, puis **le pont** qui porte le reste d'un cadre a l'autre |
| `sv_bp0` / `sv_bp1` | `0BF20Ah` / `0BF20Bh` | `BP` avant et apres la 1re evaluation — **un octet**, donc `PEEK` |
| `old_kw` / `old_disp` | `0BF20Ch` / `0BF20Fh` | les crochets d'origine |

`0BF000h`–`0BF211h`, **fichier `.obj` de 546 octets**, 2542 de marge sous `0BFC00h`.

⛔ **Les trois temoins de mesure ont ete retires**, MOD etant valide. Ils portaient `A` et `B`
tels que `dec2bin` les rendait, et le reste au sortir de la boucle ; c'est par eux que la cause
a ete trouvee **deux fois**, la ou le raisonnement s'etait trompe. Les remettre est l'affaire de
trois `mvp [!dbg_x],(BP+n)` et de trois mots de 3 octets — **le faire plutot que de deviner**,
si la fonction se remet a mentir.

## ⛔ Deux pieges d'USAGE, payes sur la machine le 2026-09-05

### Le BASIC tokenise A LA SAISIE, pas a l'execution

Si le texte d'un programme entre dans la machine **avant** le `CALL &BF000`, `MOD (17,5)` est
tokenise comme une **reference de tableau** `MOD(17,5)` -- et il le reste. Installer
l'extension ensuite n'y change rien : la ligne est deja figee. Le programme repond alors
`Array specified without DIM`, ce qui ne designe evidemment pas la vraie cause.

L'ordre est donc **impose**, et il n'est pas negociable :

1. charger le module ;
2. `CALL &BF000` ;
3. **verifier** (voir ci-dessous) ;
4. **puis seulement** charger ou saisir le programme qui emploie `MOD`.

⚠️ Cela vaut pour tout texte **re-importe** : un `.BAS` ressorti de l'emulateur et recharge
est retokenise, donc il repasse par ce piege. Un `.BSA` deja tokenise, lui, garde son jeton.

**Le controle d'installation, en deux lignes**, et il est sourcé : la ROM fait
`mvp (0D1h),[0BFD0Eh]` en `0F98CAh`, c'est-a-dire qu'elle recopie dans `basptr` les trois
octets ranges en `0BFD0Eh`. Ce que `basptr` designe est donc lisible depuis le BASIC :

```basic
W=LPEEK &BFD0E
PRINT HEX$ LPEEK (W+&90)      ' doit rendre BF1B1, l'adresse de kw_table
```

📄 Au passage, `pce500.inc` decrit `baswrk` (`0BFD0Eh`) comme « la ZONE de travail », par
opposition au POINTEUR `basptr`. La ROM dit autre chose : `0BFD0Eh` **contient** le pointeur,
et `basptr` n'en est que la copie en RAM interne. A corriger dans l'include -- c'est
exactement le genre de confusion qui a deja coute une session.

### L'import de texte MANGE LES MINUSCULES

Un `MODDIAG.BAS` ecrit en minuscules ressort de l'emulateur ampute : `'A lancer APRES avoir
installe BASEXT` devient `'A  APRES   BASEXT`. Les mots-cles et les variables, en majuscules,
survivent ; les commentaires deviennent illisibles.

**Regle : tout programme destine a la machine s'ecrit en MAJUSCULES ASCII.**

## ✅ Les fonctions chaine — la convention, etablie sur machine (2026-09-15)

Le referentiel notait « retourner une CHAINE » comme **ouvert, a etablir avant d'ecrire une
ligne ». C'est fait, calque sur les fonctions chaine de la ROM (`LEFT$`, `CHR$`, `LEN`), puis
valide sur emulateur. Les points durs, tous payes au moins une fois :

**Lire un argument chaine** (`rd1str`, d'apres `SUB_FC613` le lecteur de `LEFT$`) : `callf eval`
puis `test (BP+0),080h` — bit 7 arme = chaine, sinon **erreur 90** *Type mismatch*. Apres `eval`,
la chaine est **sur la pile U** (adresse = `U`), longueur en `(BP+4)`.

**Rendre une chaine** (`ret_str`, replique de `LOC_FD6F9`) : `(BP+0)=080h` (type chaine),
`(BP+1)=U` (adresse), `(BP+4)=longueur`, `rc`/`retf`.

- ⛔ **Le resultat doit REMPLACER l'argument sur U, sans laisser de trou**, sinon la
  concatenation `"["+TRIM$(...)` lit par-dessus le trou et corrompt `"["`. `UCASE$`/`LCASE$`
  transforment **sur place** ; `TRIM*` copient la sous-plage **au sommet** de la zone argument ;
  `REPT$`/`SREPT$` ajustent `U` pour finir la ou finissait l'argument.
- ⛔ **Le `pmdf (bp_ram),0F1h` (BP -= 15) de `LOC_FD6F9` est INDISPENSABLE**, mais APRES avoir
  ecrit le descripteur : l'interpreteur *lit* au cadre post-`eval` et *restitue* BP en attendant
  ce -15. Sans lui, BP derive de 15 par appel et le **OFF plante** apres quelques commandes ;
  avant l'ecriture, le descripteur atterrit au mauvais cadre et le resultat est corrompu.
- ⛔ **`INSTR` rend un NOMBRE** (comme `LEN`/`ASC`) : il lit les chaines, **libere** les
  temporaires de `U` (`add u,longueur`, d'apres `BAS_LEN`), et convertit par `bin2dec` — qui
  **ECRASE X** (le point de reprise), a sauver par `pushu x`/`popu x` autour de l'appel.

⛔ **Un bug de `xasm2026-4` a coute une session entiere** : `cmp a,(n)` (comparer A a la RAM
interne) **n'existe pas** dans le SC62015, mais l'assembleur l'acceptait et l'encodait sur
l'opcode `0x62` — qui est `CMP [lmn],n`, **5 octets**. Seuls 2 octets etaient emis : le CPU
avalait les 3 suivants, tombait sur un `reti` orphelin, et **revenait au MENU principal**. La
forme correcte est `cmp (n),a` (`0x63`, operandes et retenue inverses). Rapport dans
`../../../xasm2026-4/RAPPORT-BUG-cmp-a-parentheses.md` (le moteur C de reference, lui, refuse
`cmp a,(n)` avec `Undefined instruction`).

## Comment l'interpreteur nous trouve

Deux crochets dans sa zone de travail, `x = (basptr) = (0D1h)` :

```
[x+090h]   la table de mots-cles     (texte -> jeton)
[x+093h]   la table de repartition   (jeton -> routine)
```

⚠️ **Il n'y a PAS de chainage.** Chaque crochet porte **un seul** pointeur, et le balayage de
`SUB_F593D` s'arrete sur un jeton `000h`. Un second module installe ecraserait le premier :
c'est pourquoi les trois mots-cles vivent dans **un seul** module, et pourquoi il s'appelle
`BASEXT` et non `LPEEK`.

## Le drapeau qui distingue instruction et fonction

Le quartet haut du 3e octet d'adresse, dans la table de repartition :

| | | |
|---|---|---|
| `080h` | **instruction** | routine a l'adresse **telle quelle** — resolveur `0F58E5h` |
| `040h` | **fonction** | routine a l'adresse **+ 3** — resolveur `0F590Bh` |

D'ou les trois octets `db 0,0,0` devant `LPEEK` et `WPEEK`, et leur absence devant `LPOKE`.

## Les pieges, tous payes une fois

⛔ **Le nom de fichier tient en 8 caracteres.** Les noms SHARP sont en **8.3**, et ce
module s'est d'abord appele `BASIC_EXT` — neuf caracteres, un de trop. La regle vaut pour
tout ce qui part sur le lecteur, `.OBJ` comme `.UU` : `LOAD M "S1:BASEXT.OBJ"` ne pardonne
pas un nom trop long. Le `.ASM`, le `.lst` et ce fichier restent sur le PC et ne sont pas
concernes, mais les nommer autrement inviterait la confusion.

⛔ **Le nom.** Un mot-cle ajoute ne doit ni COMMENCER par un mot-cle existant, ni etre le
DEBUT de l'un d'eux. `PEEKX` fut coupe en `PEEK` + la variable `X`, et la ligne devint une
erreur de syntaxe. Se verifie sur les 168 noms de `Data/BasicTokens.csv` **avant** d'ecrire
une ligne de code.

⛔ **Les services de la ROM qui finissent par `RET`.** Depuis la page `0B`, ils sont
inutilisables : leur retour depile 2 octets et reste dans LEUR page. Il faut l'entree qui
finit par `RETF` — d'ou `chknum` = `0EFBF3h`, `dec2bin` = `0EFAD4h`, `bin2dec` = `0EFB6Fh`.

⛔ **`basptr`, pas `baswrk`.** Le pointeur est en RAM interne a `0D1h` ; `baswrk` est la ZONE,
en `0BFD0Eh`. `mv x,(baswrk)` ne proteste pas : XASM **tronque** a 8 bits et le code installe
ses crochets en `[(00Eh)+090h]`. Verifiable dans l'objet : on doit lire `30 84 D1`.

⛔ **`(BP+n)`, pas `(000h)`.** Sous `pre_on`, `(000h)` designe l'adresse directe 0 ; le mode
`(BP+n)` est celui qui n'emet **pas** d'octet PRE. Le controle se fait dans l'objet.

⛔ **Le cadre de `chknum` : ce qui est mesure, et ce qui ne l'est pas.** La boucle de `LPOKE`
appelle un `chknum` **par valeur** et rend `pmdf +15` apres chacune ; elle fonctionne sur la
machine, sur trois valeurs. Cela etablit que **le compte doit revenir a zero sur tous les
chemins**, erreurs comprises.

⚠️ Cela n'etablit **pas** ou atterrit un operande *precedent* apres un second `chknum`.
`MOD` l'a suppose — `(bp+16)..(bp+18)` — et la machine a repondu 0 pour toutes les valeurs.
`LPOKE` ne pouvait pas le reveler : il consomme chaque valeur **avant** d'appeler le `chknum`
suivant, et ne relit jamais la precedente. Une fonction a deux operandes, si. Voir plus haut :
`MOD` ne suppose plus rien, il met son premier operande a l'abri et restaure `BP` en absolu.

⛔ **`dec2bin` ne convertit que 20 bits — et cela MORD.** Le premier `TEST.BAS` ecrit ici
employait `&123456` et `&789ABC`, choisis pour être de jolies valeurs de trois octets. Les
deux depassent `0FFFFFh`, et la machine a repondu `Data out of range in 50`. La regle etait
pourtant ecrite dans ce module, deux paragraphes plus bas : elle a ete enfreinte par celui
qui venait de l'ecrire. **Une valeur de `LPOKE` est une adresse, donc 20 bits.**

⛔ **`dec2bin` ne convertit que 20 bits** (`0EFB8Bh` : 8+8+4). Une valeur au-dela de `0FFFFFh`
est tronquee **avant** de nous parvenir, sans que rien ne le signale. Sans consequence pour
l'usage vise — une adresse de cette machine fait 20 bits — mais cela devait etre dit.

⛔ **La zone d'essai est en `&BF300`, et il a fallu l'y porter deux fois.** Elle etait en
`&BF100` quand le module s'arretait a `0BF0BAh` ; `LPOKE` l'a porte a `0BF121h` et la zone
tombait dedans. Portee en `&BF200`, elle n'avait plus que **14 octets** de marge une fois
`MOD` ajoute — assez pour tenir, trop peu pour dormir tranquille. Elle est en `&BF300`, soit
**270 octets** apres la fin du module.

⚠️ **Ce chiffre est a verifier a chaque nouvelle entree.** Le module a triple de taille en
deux ajouts : 187 octets, puis 290, puis 498.

⛔ **La zone d'essai a du demenager.** `TEST.BAS` employait `&BF100`, qui tombait hors du
module quand il finissait en `0BF0BAh`. `LPOKE` l'a porte a `0BF121h` : l'essai ecrivait
desormais dans le code. Elle est en `&BF200`.

## Ce qui n'est PAS realisable par ce mecanisme

⛔ **Un operateur infixe**, du genre `A MOD B`. La reconnaissance des operateurs est **cablee
en dur** dans l'analyseur d'expression, en `0EF2C5h` :

```asm
0EF2CD  cmp  a,0A1h      ; AND ?
0EF2D1  cmp  a,0A2h      ; OR  ?
0EF2D5  cmp  a,0A5h      ; XOR ?
0EF2D9  mv   a,[--x]     ; aucun des trois : rendre le caractere
```

Trois comparaisons litterales, ni table ni plage. Nos deux crochets ne donnent pas acces a ce
test. Un modulo est donc realisable en **fonction a deux arguments** — `MOD (A,B)`, sur le
modele de `POINT (x,y)` — mais jamais en infixe.
