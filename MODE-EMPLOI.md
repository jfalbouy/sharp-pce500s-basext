# Créer une instruction BASIC — mode d'emploi et référentiel

*Rédigé le 2026-09-15 — mis à jour le 2026-09-26*

**PC-E500S, ROM 8.3.** Comment greffer ses propres mots-clés sur l'interpréteur : les
instructions standard et leur mécanique, la procédure, les adresses de la ROM à employer, et la
manière de rendre la main au BASIC.

> **Portée des adresses.** Toutes les adresses sont celles de `rom83.bin` (PC-E500S, version
> 8.3). Sur le PC-E500 (`rom53`), les mêmes tables existent mais sont **relogées** : aucune
> adresse de ce document ne s'y applique telle quelle.
>
> **Référent.** Ce document fait **autorité** sur la création d'instructions BASIC. Les autres
> documents de `C:\Claude` (référentiel, désassembleur, skill) y renvoient. En cas de désaccord,
> on corrige **ici d'abord**, puis on reporte.
>
> **Légende**, celle du dépôt : ✅ confirmé (mesuré sur machine ou lu sur deux sources) · 📖 lu
> dans la ROM, non éprouvé sur machine · ⚠️ piège ou point incertain · ⛔ erreur corrigée, gardée
> écrite avec ce qui l'a démentie. Les sources sont au §13.
>
> Le **pourquoi** détaillé (les essais, les impasses, les mesures) est dans
> `Referentiel PC-E500S SC62015/12-extensions-basic.md` et dans `JOURNAL-MISE-AU-POINT.md`. Ce
> document-ci est le **comment**, et il renvoie aux paragraphes qui justifient chaque règle.

---

## Sommaire

0. [La marche à suivre en une page](#0-la-marche-à-suivre-en-une-page)
1. [Comment l'interpréteur exécute un mot-clé](#1-comment-linterpréteur-exécute-un-mot-clé)
2. [Référentiel des 168 instructions standard](#2-référentiel-des-168-instructions-standard)
3. [Les deux crochets d'extension](#3-les-deux-crochets-dextension)
4. [Le contrat d'une routine](#4-le-contrat-dune-routine)
5. [Lire les arguments](#5-lire-les-arguments)
6. [Restituer la main à l'interpréteur](#6-restituer-la-main-à-linterpréteur)
7. [Les adresses de la ROM — référentiel](#7-les-adresses-de-la-rom--référentiel)
8. [Gabarits de code](#8-gabarits-de-code)
9. [Mise en œuvre sur la machine](#9-mise-en-œuvre-sur-la-machine)
10. [Catalogue des pièges](#10-catalogue-des-pièges)
11. [Limites du mécanisme](#11-limites-du-mécanisme)
12. [Points ouverts](#12-points-ouverts)
13. [Sources](#13-sources)

---

## 0. La marche à suivre en une page

| # | Étape | Contrôle | § |
|---|---|---|---|
| 1 | **Choisir le nom** | il ne doit ni **commencer** par un mot-clé existant, ni en être le **début** (`PEEKX` est coupé en `PEEK` + `X`) | 2, 10 |
| 2 | **Choisir un token libre** | parmi les 86 du §2.3, jamais `00h` ; de préférence un token déjà éprouvé | 2.3 |
| 3 | **Décider la nature** | *instruction* (drapeau `080h`, routine à l'adresse) ou *fonction* (drapeau `040h`, routine à l'adresse **+ 3**) | 1.3 |
| 4 | **Choisir la syntaxe à imiter** | sans parenthèses comme `PEEK` → `chknum` ; liste parenthésée comme `POINT` → `eval` ; liste à virgules comme `POKE` | 5.1 |
| 5 | **Écrire la routine** | `X` rendu avancé, `BP` selon la loi du cadre, résultat au bon format, `rc`/`retf` | 4, 6 |
| 6 | **Déclarer** | une entrée dans la table des noms **et** dans la table de répartition | 3.2 |
| 7 | **Assembler** | `xasm2026-4 BASEXT.ASM -O -L -S -B -K`, puis **vérifier l'objet** : `30 84 D1` pour `mv x,(basptr)`, pas de PRE devant les `(BP+n)` | 9.1 |
| 8 | **Réserver la zone** langage machine | le module doit tomber entre `[0BFD1Ah]` et le plafond `0BFC00h` | 9.2 |
| 9 | **Installer, vérifier, PUIS charger le programme** | le BASIC tokenise à la saisie : un programme saisi avant l'installation garde des noms de variables | 9.3 |
| 10 | **Éprouver chaque refus** | un cas par code d'erreur, et le contrôle croisé par le BASIC lui-même | 9.4 |

---

## 1. Comment l'interpréteur exécute un mot-clé

### 1.1 Trois tables, et le token comme pivot

Un mot-clé est trois choses : un **nom** (ce que l'on tape), un **token** (1 octet, ce qui est
rangé dans le programme) et une **routine** (ce qui s'exécute). Aucune table ne relie
directement le nom à la routine : le token est le pivot.

| Adresse | Table | Format |
|---|---|---|
| `0F4D9Dh` | index par lettre | 26 offsets de 2 octets, relatifs au début de la table des mots-clés |
| `0F4DD1h` | noms (token → nom, pour `LIST`) | 256 × 2 octets, offset relatif à la page `0F0000h` |
| `0F4FD1h` | **répartition** (token → routine) | **256 × 3 octets**, indexée par le token ; le quartet haut du 3e octet est le **drapeau** |
| `0F52DCh`–`0F570Ah` | **mots-clés** (nom → token) | `longueur, nom ASCII, token`, groupés par initiale, chaque groupe fermé par `00` |

✅ Les quatre tables sont **jointives** (chacune finit où commence la suivante), dans les deux
ROM — trois détections indépendantes qui se referment l'une sur l'autre
(`SC62015Disassembler/Docs/Synthese/BASIC-en-ROM.md` §§2-3bis).

### 1.2 La tokenisation se fait à la saisie

Dans un programme, un mot-clé est rangé **`0FEh` + token** (2 octets). La conversion a lieu
quand la ligne est **saisie ou importée**, pas quand elle s'exécute.

⚠️ **Le tokeniseur consulte la table de la ROM avant celle de l'extension.** Mesuré : `PEEKX` a
été coupé en `PEEK` + la variable `X`, et la ligne relue s'affichait `PRINT HEX$ PEEK X &BF100`.

### 1.3 La résolution : deux résolveurs, un drapeau

✅ Lu dans la ROM, et identique pour la table de la ROM et pour celle d'une extension :

| Résolveur | Test | Routine | Retour |
|---|---|---|---|
| instructions `0F58D8h` | `test a,080h` en `0F58E8h` sur le 3e octet | l'adresse **telle quelle** | `ret` |
| fonctions `0F590Bh` | `test a,040h` en `0F591Bh` | l'adresse **+ 3** | `retf` |

L'ordre est le suivant :
1. l'entrée du token dans la table de la ROM (`0F4FD1h`) ; si son drapeau porte le bit cherché,
   c'est elle ;
2. sinon, le balayage de la table d'extension, **`0F593Dh`** ; si l'entrée trouvée porte le bit,
   c'est elle ;
3. sinon `Y` = **`0F5960h`**, qui fait `mv a,00Ah` / `sc` / `retf` : **erreur 10, *Syntax error***.

Le quartet de drapeau vaut donc :

| Quartet | Sens | Exemple |
|---|---|---|
| `8` | instruction | `PRINT` : `8F B900` → `0FB900h` |
| `4` | fonction | `ASC` : `4F D688` → `0FD68Bh` |
| `C` | **les deux** | `INPUT` : `CF 52D1` → instruction `0F52D1h`, fonction `0F52D4h` |
| `0` | aucune routine | entrée `000000h` |

⚠️ **Le « + 3 » n'est pas un descripteur.** Les trois octets qui précèdent une fonction de la ROM
sont la queue de la routine précédente (`25 03 06` devant `ASC` : `06h` = `RET`). La règle est
uniforme parce que les tokens doubles commencent par un saut de 3 octets. **Pour une fonction
d'extension, ranger `routine − 3` et faire précéder la routine de trois octets quelconques**
(`db 0,0,0`).

✅ **Les quatre bits de poids fort ne sont pas masqués, ils sont ignorés** : le PC fait 20 bits.
C'est ce qui permet au drapeau de tenir dans le même mot que l'adresse.

---

## 2. Référentiel des 168 instructions standard

### 2.1 D'où vient cette table

Elle est **générée depuis l'image ROM** par `outils/extraire_tokens.py`, qui lit la table des
mots-clés et la table de répartition. Elle n'est pas recopiée à la main. Chaque exécution la
**recoupe** avec le carnet relevé à la main, `SC62015Disassembler/Data/BasicTokens.csv` :

| Recoupement | Résultat |
|---|---|
| nom, token, adresse dans la table des mots-clés | **168 / 168** identiques |
| adresse de la routine | **166 / 168** identiques |
| les 2 écarts | `RESERVED` et `OPEN$` : **aucune entrée de répartition** dans l'image, là où le carnet porte `0F5960h` (la routine de refus) |

Les données brutes, sur lesquelles on peut filtrer, sont dans `donnees/tokens-rom83.csv`.

**Bilan des natures** : 98 instructions, 62 fonctions, 6 doubles, 2 sans routine.

### 2.2 Ce que la table apprend, avant de la lire

- **Les six tokens doubles** (`C`) sont `BTEXT$`, `BDATA$`, `MEM$`, `OPEN`, `INPUT`, `KEY`. Pour
  `INPUT` et `OPEN`, la seconde entrée est la **variante `$`** : `INPUT$` (`0F52D4h`) et `OPEN$`
  (`0FE20Ch`). Ni `INPUT$` ni la routine de `OPEN$` n'ont d'entrée propre (`BASIC-en-ROM.md`
  §3ter et §3quinquies).
- **Six mots-clés passifs** mènent au refus `0F5960h` : `TO`, `STEP`, `THEN`, `OUTPUT`, `APPEND`,
  `AS`. Ils ne sont reconnus qu'à l'intérieur d'une autre instruction.
- **Routines partagées** : `AND`/`OR`/`XOR` en `0EF2B9h` ; `ARUN`/`AUTOGOTO`/`DATA` en `0FD00Ah`.
- **Onze routines hors de `rom83`**, en `030E39h`–`03144Ah` : le BASIC structuré (`IF`, `ELSE`,
  `ENDIF`, `REPEAT`, `UNTIL`, `WHILE`, `WEND`, `SWITCH`, `CASE`, `DEFAULT`, `ENDSWITCH`), dans la
  ROM d'extension `S3EXT.bin`.
- **Deux entrées de répartition n'ont pas de mot-clé** : `38h` → instruction `0F7AE2h`, et `A6h`
  → fonction `0F920Bh`. ⚠️ Ces deux tokens ne sont donc **pas libres**, bien qu'aucun nom ne les
  désigne.

### 2.3 Les tokens libres

**86 tokens** n'ont ni mot-clé ni entrée de répartition (`000000h`) :

```
01 02 03 04 05 06 07 08 09 0A 0E 0F 1E 1F 39 45 48 49 4A 4B 4C 63 A8 A9 AA AB AC
B4 B5 B8 B9 BA BB BC BD C2 C3 C4 C5 C6 C7 C8 C9 CA CB CC CD CE CF D3 D4 D5 D6 D7
D8 D9 DA DB DC DD DE DF E0 E1 E2 E3 E4 E5 E6 E7 ED EE EF F3 F4 F5 F6 F7 F8 F9 FA
FB FC FD FE FF
```

⛔ **Le dépôt écrivait « 88 tokens libres »** (`12-extensions-basic.md` §2, `Routines-ROM-PC-E500S.asm`),
soit 256 − 168. La lecture de la répartition en retire **deux**, `38h` et `A6h`, qui ont une
routine sans avoir de nom.

| Tokens | Statut |
|---|---|
| `07h` `0Ah` `0Eh` `0Fh` `C2h`–`C9h` | ✅ **éprouvés sur machine** par BASEXT (2026-09-05 et 2026-09-15) |
| `CAh` `CFh` | ✅ **éprouvés** par BASEXT (`XCONSOLE`, `XCLS`, `essais/XCONTEST.BAS`) |
| `04h` `05h` `06h` `08h` `09h` `0Fh` `4Bh` `CBh`–`CEh` | employés par BASCOM (TORO, 1994) ; ⚠️ son `4Fh` est pris par `UNTIL` sur le 500S |
| `1Eh` `1Fh` `FEh` `FFh` | ⚠️ **non éprouvés**. Ces valeurs ont un rôle dans le texte tokenisé (compte de saut, référence de ligne, échappement, fin). Rien n'indique de conflit, puisqu'un token suit toujours un `0FEh`, mais **aucun essai ne l'a vérifié** : les éviter tant qu'un essai n'a pas été fait |
| `00h` | ⛔ **exclu** : il termine la table de répartition d'une extension |

⚠️ Deux extensions qui emploient le même token ne coexistent pas (§11), mais un programme
tokenisé sous l'une se relit faussement sous l'autre : `0Fh` vaut `MOD` pour BASEXT et `ORG` pour
BASCOM.

### 2.4 La table

*Nature* : ce que dit le drapeau. *Table des mots-clés* : l'adresse de l'entrée
`longueur + nom + token`. *Routine* : l'adresse **exécutée**, « + 3 » déjà appliqué pour une
fonction.

| Code | Mot-clé | Nature | Drapeau | Table des mots-clés | Routine |
|---|---|---|---|---|---|
| `00h` | `RESERVED` | aucune entrée | `0` | `0F564Dh` | — (`0F5960h`, erreur 10) |
| `0Bh` | `BTEXT$` | instruction et fonction | `C` | `0F533Eh` | `0FA28Ch` / `0FA28Fh` |
| `0Ch` | `BDATA$` | instruction et fonction | `C` | `0F5346h` | `0FA2BDh` / `0FA2C0h` |
| `0Dh` | `MEM$` | instruction et fonction | `C` | `0F554Fh` | `0FA35Eh` / `0FA361h` |
| `10h` | `RUN` | instruction | `8` | `0F55E7h` | `0FD00Fh` |
| `11h` | `NEW` | instruction | `8` | `0F5573h` | `0FA0ABh` |
| `12h` | `CONT` | instruction | `8` | `0F534Fh` | `0FD04Eh` |
| `13h` | `PASS` | instruction | `8` | `0F55A8h` | `0F8786h` |
| `14h` | `LIST` | instruction | `8` | `0F54E1h` | `0F9E5Fh` |
| `15h` | `LLIST` | instruction | `8` | `0F54E7h` | `0FCB53h` |
| `16h` | `CLOAD` | instruction | `8` | `0F5365h` | `0FE05Fh` |
| `17h` | `MERGE` | instruction | `8` | `0F5555h` | `0EC313h` |
| `18h` | `LOAD` | instruction | `8` | `0F5511h` | `0EC325h` |
| `19h` | `RENUM` | instruction | `8` | `0F5628h` | `0F8B91h` |
| `1Ah` | `AUTO` | instruction | `8` | `0F5316h` | `0F8887h` |
| `1Bh` | `DELETE` | instruction | `8` | `0F53F0h` | `0F8A7Bh` |
| `1Ch` | `FILES` | instruction | `8` | `0F5451h` | `0F8207h` |
| `1Dh` | `INIT` | instruction | `8` | `0F54CDh` | `0DFC87h` |
| `20h` | `CSAVE` | instruction | `8` | `0F536Ch` | `0FDF76h` |
| `21h` | `OPEN` | instruction et fonction | `C` | `0F5587h` | `0FE209h` / `0FE20Ch` |
| `22h` | `CLOSE` | instruction | `8` | `0F537Eh` | `0FE67Fh` |
| `23h` | `SAVE` | instruction | `8` | `0F567Bh` | `0FD8E6h` |
| `24h` | `CONSOLE` | instruction | `8` | `0F5355h` | `0FE891h` |
| `25h` | `RANDOMIZE` | instruction | `8` | `0F5608h` | `0EE439h` |
| `26h` | `DEGREE` | instruction | `8` | `0F53D2h` | `0ECF36h` |
| `27h` | `RADIAN` | instruction | `8` | `0F561Bh` | `0ECF5Eh` |
| `28h` | `GRAD` | instruction | `8` | `0F5482h` | `0ECF4Ah` |
| `29h` | `BEEP` | instruction | `8` | `0F5331h` | `0F7982h` |
| `2Ah` | `WAIT` | instruction | `8` | `0F56DEh` | `0FC6A9h` |
| `2Bh` | `GOTO` | instruction | `8` | `0F5464h` | `0FCDA3h` |
| `2Ch` | `TRON` | instruction | `8` | `0F56B2h` | `0F877Ch` |
| `2Dh` | `TROFF` | instruction | `8` | `0F56B8h` | `0F8781h` |
| `2Eh` | `CLEAR` | instruction | `8` | `0F535Eh` | `0FB458h` |
| `2Fh` | `USING` | instruction | `8` | `0F56C9h` | `0FC519h` |
| `30h` | `DIM` | instruction | `8` | `0F53CDh` | `0FB742h` |
| `31h` | `CALL` | instruction | `8` | `0F5385h` | `0F9EBBh` |
| `32h` | `POKE` | instruction | `8` | `0F55B8h` | `0F9EF2h` |
| `33h` | `GPRINT` | instruction | `8` | `0F5471h` | `0FD350h` |
| `34h` | `PSET` | instruction | `8` | `0F55C5h` | `0FD2D6h` |
| `35h` | `PRESET` | instruction | `8` | `0F55CBh` | `0FD2F7h` |
| `36h` | `BASIC` | instruction | `8` | `0F5337h` | `0F89A8h` |
| `37h` | `TEXT` | instruction | `8` | `0F56ACh` | `0F8A28h` |
| `3Ah` | `ERASE` | instruction | `8` | `0F5427h` | `0FB530h` |
| `3Bh` | `LFILES` | instruction | `8` | `0F552Eh` | `0F820Bh` |
| `3Ch` | `KILL` | instruction | `8` | `0F54D5h` | `0FDB05h` |
| `3Dh` | `COPY` | instruction | `8` | `0F5397h` | `0FF02Eh` |
| `3Eh` | `NAME` | instruction | `8` | `0F5568h` | `0FDB9Dh` |
| `3Fh` | `SET` | instruction | `8` | `0F5687h` | `0FDCADh` |
| `40h` | `LTEXT` | instruction | `8` | `0F5536h` | `0E668Bh` |
| `41h` | `GRAPH` | instruction | `8` | `0F5488h` | `0E66A4h` |
| `42h` | `LF` | instruction | `8` | `0F553Dh` | `0E66B3h` |
| `43h` | `CSIZE` | instruction | `8` | `0F539Dh` | `0E672Bh` |
| `44h` | `COLOR` | instruction | `8` | `0F53A4h` | `0E67F1h` |
| `46h` | `DEFDBL` | instruction | `8` | `0F53F8h` | `0F88E9h` |
| `47h` | `DEFSNG` | instruction | `8` | `0F5400h` | `0F88EDh` |
| `4Dh` | `ENDIF` | instruction | `8` | `0F56F8h` | `030FE0h` |
| `4Eh` | `REPEAT` | instruction | `8` | `0F5657h` | `03114Fh` |
| `4Fh` | `UNTIL` | instruction | `8` | `0F56D0h` | `031165h` |
| `50h` | `CLS` | instruction | `8` | `0F538Bh` | `0FC632h` |
| `51h` | `LOCATE` | instruction | `8` | `0F54F6h` | `0FC64Fh` |
| `52h` | `TO` | instruction | `8` | `0F56BFh` | `0F5960h` |
| `53h` | `STEP` | instruction | `8` | `0F5681h` | `0F5960h` |
| `54h` | `THEN` | instruction | `8` | `0F56A1h` | `0F5960h` |
| `55h` | `ON` | instruction | `8` | `0F5583h` | `0FCE8Bh` |
| `56h` | `IF` | instruction | `8` | `0F54BCh` | `030E39h` |
| `57h` | `FOR` | instruction | `8` | `0F544Ch` | `0FD0B8h` |
| `58h` | `LET` | instruction | `8` | `0F551Dh` | `0FB16Fh` |
| `59h` | `REM` | instruction | `8` | `0F5623h` | `0F9F9Bh` |
| `5Ah` | `END` | instruction | `8` | `0F5418h` | `0FD08Bh` |
| `5Bh` | `NEXT` | instruction | `8` | `0F5562h` | `0FD23Dh` |
| `5Ch` | `STOP` | instruction | `8` | `0F5660h` | `0FD07Ch` |
| `5Dh` | `READ` | instruction | `8` | `0F55F4h` | `0FCA07h` |
| `5Eh` | `DATA` | instruction | `8` | `0F53E4h` | `0FD00Ah` |
| `5Fh` | `PAUSE` | instruction | `8` | `0F55D3h` | `0FB897h` |
| `60h` | `PRINT` | instruction | `8` | `0F55A1h` | `0FB900h` |
| `61h` | `INPUT` | instruction et fonction | `C` | `0F54B5h` | `0F52D1h` / `0F52D4h` |
| `62h` | `GOSUB` | instruction | `8` | `0F546Ah` | `0FCE2Ah` |
| `64h` | `LPRINT` | instruction | `8` | `0F54EEh` | `0FB8C6h` |
| `65h` | `RETURN` | instruction | `8` | `0F55ECh` | `0FCFA0h` |
| `66h` | `RESTORE` | instruction | `8` | `0F55FAh` | `0FCB27h` |
| `67h` | `CHAIN` | instruction | `8` | `0F5390h` | `0EC31Bh` |
| `68h` | `GCURSOR` | instruction | `8` | `0F5479h` | `0FD312h` |
| `69h` | `LINE` | instruction | `8` | `0F5517h` | `0FD40Ah` |
| `6Ah` | `LLINE` | instruction | `8` | `0F5541h` | `0E692Ch` |
| `6Bh` | `RLINE` | instruction | `8` | `0F562Fh` | `0E6C05h` |
| `6Ch` | `GLCURSOR` | instruction | `8` | `0F548Fh` | `0E6831h` |
| `6Dh` | `SORGN` | instruction | `8` | `0F568Ch` | `0E68A0h` |
| `6Eh` | `CROTATE` | instruction | `8` | `0F53ABh` | `0E68B3h` |
| `6Fh` | `CIRCLE` | instruction | `8` | `0F53B4h` | `0E6CB9h` |
| `70h` | `PAINT` | instruction | `8` | `0F55DAh` | `0E6FCCh` |
| `71h` | `OUTPUT` | instruction | `8` | `0F5591h` | `0F5960h` |
| `72h` | `APPEND` | instruction | `8` | `0F52FAh` | `0F5960h` |
| `73h` | `AS` | instruction | `8` | `0F5302h` | `0F5960h` |
| `74h` | `ARUN` | instruction | `8` | `0F5306h` | `0FD00Ah` |
| `75h` | `AUTOGOTO` | instruction | `8` | `0F530Ch` | `0FD00Ah` |
| `76h` | `ELSE` | instruction | `8` | `0F543Fh` | `030F83h` |
| `77h` | `RESUME` | instruction | `8` | `0F5645h` | `0FD1CBh` |
| `78h` | `ERROR` | instruction | `8` | `0F5438h` | `0F5964h` |
| `79h` | `KEY` | instruction et fonction | `C` | `0F54DBh` | `0FA8C8h` / `0FA8CBh` |
| `7Ah` | `WHILE` | instruction | `8` | `0F56E4h` | `030FF4h` |
| `7Bh` | `WEND` | instruction | `8` | `0F56EBh` | `031081h` |
| `7Ch` | `SWITCH` | instruction | `8` | `0F5698h` | `0311A9h` |
| `7Dh` | `CASE` | instruction | `8` | `0F53C6h` | `0313ABh` |
| `7Eh` | `DEFAULT` | instruction | `8` | `0F5408h` | `0313D5h` |
| `7Fh` | `ENDSWITCH` | instruction | `8` | `0F56FFh` | `03144Ah` |
| `80h` | `MDF` | fonction | `4` | `0F555Ch` | `0EED1Bh` |
| `81h` | `REC` | fonction | `4` | `0F5640h` | `0EE6BFh` |
| `82h` | `POL` | fonction | `4` | `0F55E1h` | `0EE6CDh` |
| `83h` | `ROT` | fonction | `4` | `0F5636h` | `0EDB0Dh` |
| `84h` | `DECI` | fonction | `4` | `0F5411h` | `0EEAEEh` |
| `85h` | `HEX` | fonction | `4` | `0F54A0h` | `0EEAFEh` |
| `86h` | `TEN` | fonction | `4` | `0F56C3h` | `0ED6A2h` |
| `87h` | `RCP` | fonction | `4` | `0F563Bh` | `0ECBE3h` |
| `88h` | `SQU` | fonction | `4` | `0F5693h` | `0ECBCAh` |
| `89h` | `CUR` | fonction | `4` | `0F53C1h` | `0EDFE6h` |
| `8Ah` | `HSN` | fonction | `4` | `0F54A5h` | `0EE03Fh` |
| `8Bh` | `HCS` | fonction | `4` | `0F54AAh` | `0EE048h` |
| `8Ch` | `HTN` | fonction | `4` | `0F54AFh` | `0EE051h` |
| `8Dh` | `AHS` | fonction | `4` | `0F531Ch` | `0EE05Ah` |
| `8Eh` | `AHC` | fonction | `4` | `0F5321h` | `0EE063h` |
| `8Fh` | `AHT` | fonction | `4` | `0F5326h` | `0EE06Ch` |
| `90h` | `FACT` | fonction | `4` | `0F545Dh` | `0EE35Fh` |
| `91h` | `LN` | fonction | `4` | `0F550Dh` | `0EDAEFh` |
| `92h` | `LOG` | fonction | `4` | `0F54FEh` | `0EDAF8h` |
| `93h` | `EXP` | fonction | `4` | `0F541Dh` | `0ED6ABh` |
| `94h` | `SQR` | fonction | `4` | `0F5666h` | `0ECDFFh` |
| `95h` | `SIN` | fonction | `4` | `0F566Bh` | `0ECF6Dh` |
| `96h` | `COS` | fonction | `4` | `0F5373h` | `0ECF76h` |
| `97h` | `TAN` | fonction | `4` | `0F56A7h` | `0ECF7Fh` |
| `98h` | `INT` | fonction | `4` | `0F54C0h` | `0EE4D0h` |
| `99h` | `ABS` | fonction | `4` | `0F52E6h` | `0EE4C7h` |
| `9Ah` | `SGN` | fonction | `4` | `0F5670h` | `0EE84Fh` |
| `9Bh` | `DEG` | fonction | `4` | `0F53DAh` | `0EE87Ch` |
| `9Ch` | `DMS` | fonction | `4` | `0F53DFh` | `0EE885h` |
| `9Dh` | `ASN` | fonction | `4` | `0F52F0h` | `0ED3F8h` |
| `9Eh` | `ACS` | fonction | `4` | `0F52F5h` | `0ED401h` |
| `9Fh` | `ATN` | fonction | `4` | `0F52EBh` | `0ED40Ah` |
| `A0h` | `RND` | fonction | `4` | `0F5603h` | `0EE9F9h` |
| `A1h` | `AND` | fonction | `4` | `0F52E1h` | `0EF2B9h` |
| `A2h` | `OR` | fonction | `4` | `0F558Dh` | `0EF2B9h` |
| `A3h` | `NOT` | fonction | `4` | `0F556Eh` | `0EE490h` |
| `A4h` | `PEEK` | fonction | `4` | `0F55B2h` | `0F9F44h` |
| `A5h` | `XOR` | fonction | `4` | `0F56F2h` | `0EF2B9h` |
| `A7h` | `EVAL` | fonction | `4` | `0F5445h` | `0EEF55h` |
| `ADh` | `POINT` | fonction | `4` | `0F55BEh` | `0FD322h` |
| `AEh` | `PI` | fonction | `4` | `0F55AEh` | `0EEC74h` |
| `AFh` | `FRE` | fonction | `4` | `0F5458h` | `0FA06Ch` |
| `B0h` | `EOF` | fonction | `4` | `0F5422h` | `0FDF46h` |
| `B1h` | `DSKF` | fonction | `4` | `0F53EAh` | `0FDD99h` |
| `B2h` | `LOF` | fonction | `4` | `0F5503h` | `0FDF17h` |
| `B3h` | `LOC` | fonction | `4` | `0F5508h` | `0FDE7Eh` |
| `B6h` | `NCR` | fonction | `4` | `0F5578h` | `0EE4F5h` |
| `B7h` | `NPR` | fonction | `4` | `0F557Dh` | `0EE4FEh` |
| `BEh` | `AER` | fonction | `4` | `0F532Bh` | `0EEE4Ah` |
| `BFh` | `CUB` | fonction | `4` | `0F53BCh` | `0EE023h` |
| `C0h` | `ERN` | fonction | `4` | `0F5433h` | `0F9F8Ch` |
| `C1h` | `ERL` | fonction | `4` | `0F542Eh` | `0F9F77h` |
| `D0h` | `ASC` | fonction | `4` | `0F52DCh` | `0FD68Bh` |
| `D1h` | `VAL` | fonction | `4` | `0F56D8h` | `0EECC3h` |
| `D2h` | `LEN` | fonction | `4` | `0F5522h` | `0EECA8h` |
| `E8h` | `OPEN$` | aucune entrée | `0` | `0F5599h` | — (`0F5960h`, erreur 10) |
| `E9h` | `INKEY$` | fonction | `4` | `0F54C5h` | `0F9FA1h` |
| `EAh` | `MID$` | fonction | `4` | `0F5549h` | `0FD75Ah` |
| `EBh` | `LEFT$` | fonction | `4` | `0F5527h` | `0FD747h` |
| `ECh` | `RIGHT$` | fonction | `4` | `0F5613h` | `0FD706h` |
| `F0h` | `CHR$` | fonction | `4` | `0F5378h` | `0FD6BDh` |
| `F1h` | `STR$` | fonction | `4` | `0F5675h` | `0FD6CDh` |
| `F2h` | `HEX$` | fonction | `4` | `0F549Ah` | `0FD7F7h` |

⚠️ **`AND`, `OR` et `XOR` sont déclarés « fonction », mais ne passent pas par le résolveur** quand
ils sont employés en infixe : l'analyseur d'expression les reconnaît par trois comparaisons
littérales, en `0EF2CDh`, `0EF2D1h` et `0EF2D5h` (§11).

---

## 3. Les deux crochets d'extension

### 3.1 Où ils sont

| | Adresse | |
|---|---|---|
| `basptr` | RAM interne **`0D1h`**, 3 octets | le pointeur vers la zone de travail du BASIC ; ✅ la ROM le recopie depuis `[0BFD0Eh]` par `mvp (basptr),[baswrk]` en `0F98C9h` |
| crochet des noms | **`[(basptr)+090h]`** | adresse de la table des noms de l'extension |
| crochet de répartition | **`[(basptr)+093h]`** | adresse de la table de répartition de l'extension |
| sentinelle | `0FFFFFh` | ✅ écrite dans les deux crochets par `0F93C3h` : « aucune extension » |

⛔ **`basptr` (`0D1h`, RAM interne) et non `baswrk` (`0BFD0Eh`, mémoire externe).**
`mv x,(baswrk)` ne proteste pas : XASM **tronque** l'adresse à 8 bits, et le module installe ses
crochets en `[(00Eh)+090h]`. Le contrôle se fait dans l'**objet** : `30 84 D1`, jamais
`30 84 0E` (`12-extensions-basic.md` §7).

### 3.2 Le format des deux tables

```asm
kw_table:                               ; nom -> token
        db      5,'LPEEK',007H          ; longueur, lettres, token
        db      3,'MOD',00FH
        db      0                       ; fin de table

disp_table:                             ; token -> routine, 4 octets par entree
        db      007H, lpeek_m3, lpeek_m3/256, lpeek_m3/65536+040H   ; fonction : adresse - 3
        db      00EH, lpoke,    lpoke/256,    lpoke/65536+080H      ; instruction : adresse
        db      0                       ; fin de table
```

📖 Le balayage de `0F593Dh` : il lit le crochet de répartition, conclut « absent » s'il vaut
`0FFFFFh`, puis compare le token entrée par entrée (pas de 4), s'arrête sur un token `00h`, et
rend `Y` sur les **trois octets d'adresse** de l'entrée trouvée.

⚠️ **Contrairement à la table de la ROM, celle d'une extension n'est pas groupée par initiale** :
un seul `00` à la fin (BASCOM et BASEXT, tous deux éprouvés).

### 3.3 L'installation, idempotente

```asm
start:
        pushu   x               ; X porte le point de reprise de l'interpreteur
        pushu   i
        mv      x,(basptr)      ; objet : 30 84 D1
        mv      a,[x+092H]      ; poids fort du crochet des noms
        cmp     a,00FH          ; encore la sentinelle 0FFFFFh ?
        jrnz    deja_ext        ; non : ne pas ecraser la sauvegarde
        mv      y,[x+090H]
        mv      [old_kw],y
        mv      y,[x+093H]
        mv      [old_disp],y
deja_ext:
        mv      y,kw_table
        mv      [x+090H],y
        mv      y,disp_table
        mv      [x+093H],y
        popu    i
        popu    x
        rc                      ; carry CLAIR : retour propre au BASIC
        retf
```

⛔ Sans le test de sentinelle, un second `CALL` écrase `old_kw`/`old_disp` avec les tables du
module lui-même, et la désinstallation est perdue. Constaté sur machine le 2026-09-05
(`12-extensions-basic.md` §12).

### 3.4 Vérifier l'installation depuis le BASIC

Il suffit de relire le crochet des noms : il doit désigner `kw_table`, dont l'adresse se lit
**dans le `.lst` de la version chargée** et jamais de mémoire (`0BF62Ch` pour la version de
1740 octets).

```basic
W=LPEEK &BFD0E
PRINT HEX$ LPEEK (W+&90)
```

Sans `LPEEK` (avant l'installation, ou pour une autre extension), la même chose avec `PEEK`,
qui ne lit qu'un terme :

```basic
W=PEEK &BFD0E+PEEK &BFD0F*256+PEEK &BFD10*65536
PRINT HEX$ (PEEK (W+&90)+PEEK (W+&91)*256+PEEK (W+&92)*65536)
```

---

## 4. Le contrat d'une routine

| | À l'entrée | À la sortie |
|---|---|---|
| **`X`** | pointe l'octet qui **suit** le token | pointe l'octet qui **suit** ce que la routine a consommé ; sur un caractère refusé, le **remettre** (`dec x`) |
| **`BP`** (RAM interne `0ECh`) | le cadre courant ; ✅ mesuré à **150** (`096h`) à l'entrée d'une fonction, **190** (`0BEh`) au moment d'un `CALL` | voir la **loi du cadre**, §6.1 |
| **`(BP+0)`** | ⚠️ **le statut BASIC**, pas une case libre (bit 2 : exécution programme ou directe ; bit 4 : mode PRO/RUN) | l'octet de type du résultat (§6) |
| **`U`** | la pile utilisateur ; les chaînes temporaires y vivent | équilibrée : le résultat **remplace** les arguments (§6.3) |
| **`I`** | — | à préserver (`pushu`/`popu`) |
| **retenue** | — | **claire** = succès ; **armée** = erreur, et `A` porte le code BASIC |
| **retour** | appel par le résolveur | **`retf` obligatoire** pour une fonction |

⚠️ **Une extension vit en page `0B`, les services en `0E` et `0F`.** Un service qui finit par
`ret` ne se laisse pas appeler d'une autre page : son retour dépile 2 octets et reste dans
**sa** page. Il faut, pour chaque service, l'entrée qui finit par **`retf`** (§7.1).

⚠️ **L'oubli de `X` ne plante pas.** Le mot-clé est reconnu, la routine s'exécute, et
l'interpréteur reprend n'importe où : *Syntax error* sans autre indice.

---

## 5. Lire les arguments

### 5.1 Choisir l'évaluateur d'après la syntaxe imitée

| Entrée | Ce qu'elle lit | Type | Cadre | Modèle ROM |
|---|---|---|---|---|
| **`chknum`** `0EFBF3h` | **un terme** : nombre, variable, appel de fonction, ou expression **entre parenthèses** — elle s'arrête au premier opérateur | ✅ vérifie « numérique » ; sur une chaîne, la libère de `U` (`call 0EF104h`) et rend l'**erreur 90** (`0EFC04h`) | ✅ −15, mesuré (150 → 135) | `PEEK` (`0F5F9Ch`) |
| **`eval`** `0EF26Eh` | **une expression complète**, opérateurs compris | ⚠️ **ne vérifie pas** : l'appelant teste `(BP+0)` bit 7 (chaîne) lui-même, comme la ROM en `0F5F6Bh` | ✅ −15, mesuré (135 → 120) | `POINT` (`0F5F65h`), `LEFT$` (`0FC613h`) |

**La règle en une phrase** : sans parenthèses, à la manière de `PEEK`, prendre `chknum` ; avec
une liste parenthésée, à la manière de `POINT`, prendre `eval`. D'où
`PEEK &BFD1C*&100` = `(PEEK &BFD1C)*&100`.

⛔ Mesuré avec `MOD` sous `chknum` : `MOD (17,5)` et `MOD (A,B)` passaient, mais `MOD (A+1,B)` et
`MOD (I*3571,997)` échouaient. Sous `eval`, `MOD (ASC "A",5)` rend `0`, ce qui est juste
(`12-extensions-basic.md` §8).

📖 Si `eval` échoue sans code d'erreur (`A` = 0), il pose **22**, *Illegal function call*
(`0EF289h`).

### 5.2 Convertir un nombre en entier

**`dec2bin`** `0EFAD4h` : convertit le nombre du cadre en entier binaire.

| | |
|---|---|
| sortie | entier en **`(BP+1)`..`(BP+3)`**, petit-boutien ; le **signe** reste dans le **bit 3 de `(BP+0)`** — la valeur absolue est rendue, c'est à l'appelant de refuser un négatif |
| borne | ✅ **refuse toute valeur ≥ 1 048 576** (2²⁰) : retenue sur l'accumulation dans `X` (`0EFAFBh`, `0EFB04h`…) puis `mv a,021h` en `0EFB16h` → **erreur 33**. Mesuré trois fois : `MOD (1048576,5)`, `TEST.BAS` avec `&123456`, et `BEXTTEST.BAS` ligne 60 (2026-09-15) |
| chaîne | 📖 renvoie l'erreur 90 (`jpnz 0EFC01h` en `0EFADBh`) |
| ⚠️ en échec | il **rend déjà son cadre** : `LOC_ECB5C` fait `sc` / `pmdf (bp_ram),00Fh` / `ret`. Ne pas rendre un cadre de plus |

Deux enveloppes de la ROM, à lire comme modèles et **à ne pas appeler** (elles finissent par
`ret`) :

| | |
|---|---|
| `0F5C58h` | `dec2bin`, puis refus hors `0..255` ou négatif (erreur 33), `A` = la valeur, **`pmdf +15`** |
| `0F5C9Ah` | `dec2bin`, refus d'un négatif, `Y` = la valeur 20 bits, **`pmdf +15`** |

### 5.3 La ponctuation

| Forme | Modèle ROM | Règle |
|---|---|---|
| espaces | `0FB2D9h` | 📖 **regarde** `[x]` sans consommer, avance tant qu'il lit `20h`, laisse `X` **sur** le premier non-espace |
| `(a,b)` | `0FD5E7h`, lecteur de `POINT` | ✅ exige **trois** caractères : `(` en `0FD5ECh`, `,` en `0FD5F9h`, `)` en `0FD60Ah` ; sur un caractère refusé, `dec x` puis erreur 10 (`0FD619h`) |
| liste `a,b,c` | `0F9EF2h`, `POKE` | ✅ lit un caractère ; si ce n'est pas `,`, le **remet** (`dec x` en `0F9F30h`) et termine |

⛔ **La parenthèse ouvrante se consomme dans VOTRE code.** Laissée à l'évaluateur, `(17,5)` est
pris pour une expression parenthésée qui bute sur la virgule : *Syntax error*.

### 5.4 Lire une chaîne

✅ Établi sur machine le 2026-09-14 sur le modèle de `LEFT$`, dont le lecteur est `0FC613h` :
`callf eval` / `test (000h),080h` / erreur 90 si ce n'est pas une chaîne.

Après `eval`, le cadre porte le **moule de chaîne** (15 octets, dont 5 utiles) :

| Octet | Contenu |
|---|---|
| `(BP+0)` | `80h` : type chaîne |
| `(BP+1)`..`(BP+3)` | adresse de la chaîne |
| `(BP+4)` | longueur |

et la chaîne elle-même est **sur la pile `U`, à l'adresse `U`**. Deux chaînes lues à la suite
s'empilent : la seconde à `U`, la première juste au-dessus (`U` + longueur de la seconde) —
c'est la disposition qu'emploie `INSTR`.

✅ **Un argument peut être d'un type ou de l'autre** : `INSTR ([début,] t$, r$)` teste le bit 7
après le premier `eval` et choisit sa lecture.

---

## 6. Restituer la main à l'interpréteur

### 6.1 La loi du cadre

**Une fonction rend la main avec `BP` = `BP` d'entrée − 15, son résultat écrit dans ce cadre.
Une instruction rend `BP` inchangé. Une erreur rend `BP` d'entrée.**

Chaque routine de la ROM lue la respecte, par des chemins différents :

| Routine | Lecture | Rendu | `BP` net |
|---|---|---|---|
| `PEEK` `0F9F44h` | `0F5F9Ch` = `chknum` (−15) + `0F5C9Ah` (+15) | `pmdf −15` en `0F9F4Ah` | **−15** |
| `CHR$` `0FD6BDh` | `chknum` (−15) + `0F5C58h` (+15) | `pmdf −15` en `0FD6F9h` | **−15** |
| `LEFT$` `0FD747h` | `0FC613h` = `eval` (−15) | **aucun `pmdf`**, `0FD7D3h` | **−15** |
| `LEN` `0EECA8h` | `0EF88Ch`, l'évaluateur de terme qu'enveloppe `chknum` | aucun `pmdf` | **−15** |
| `POKE` `0F9EF2h` (instruction) | `pmdf −4` en `0F9EF7h`, lectures à bilan nul | `pmdf +4` en `0F9F32h` | **0** (📖 `0F9EDBh`, appelé en tête, non lu) |
| BASEXT `LPEEK`, `WPEEK` | `chknum` (−15) | aucun | ✅ **−15**, machine |
| BASEXT `MOD`, `REPT$`, `SREPT$`, `INSTR` | plusieurs `eval` | `BP` restauré **en absolu** au cadre du 1er `eval` (`sv_bp1`) | ✅ **−15**, machine |
| BASEXT `LPOKE` (instruction) | `chknum` (−15) puis `pmdf +15` **à chaque valeur** | — | ✅ **0**, machine |

⛔ **« Le `pmdf (bp_ram),0F1h` est INDISPENSABLE pour rendre une chaîne » — c'était faux en
général.** Le README de BASEXT l'affirmait, ainsi que l'en-tête de `STREXT.ASM`, en citant
`LOC_FD6F9`. Or `LOC_FD6F9` est la fin de **`CHR$`**, dont le lecteur a **déjà rendu** son cadre
(`0F5C58h` fait `+15`) : son `−15` ne fait que reconstituer le cadre du résultat. **`LEFT$`**, qui
lit par `eval` et garde le cadre, finit en `LOC_FD7D3` **sans aucun `pmdf`**, et le `ret_str` de
l'objet validé le 2026-09-15 n'en contient pas non plus (`0BF219h` :
`CC 00 80 / A6 01 / A1 04 / 9F / 07`). La mesure du 2026-09-14 citée à l'appui ne se rattache à
aucune version conservée du code ; la ROM et l'objet validé disent l'inverse. **Ce qui compte
est le compte net**, pas la présence d'un `pmdf`.

**Conduite recommandée** : sauver `BP` **en absolu** plutôt que de compter des `pmdf` — deux
octets de RAM, et le compte ne peut plus être faux.

```asm
        mv      [!sv_bp0],(bp_ram)      ; a l'entree : l'etat a rendre en erreur
        callf   eval
        mv      [!sv_bp1],(bp_ram)      ; apres le 1er eval : le cadre du resultat
        ...
        mv      (bp_ram),[!sv_bp1]      ; pour rendre le resultat
        mv      (bp_ram),[!sv_bp0]      ; sur tout chemin d'erreur
```

⚠️ Sous `pre_on`, `(bp_ram)` est un opérande **absolu** : l'objet doit porter l'octet PRE.
Dans la version de 1740 octets, `mv [!sv_bp1],(bp_ram)` s'assemble en `30 D8 B9 F6 0B EC`
(`0BF11Eh`, `sv_bp1` = `0BF6B9h`) ; sans le `30` de tête, l'écriture partirait en `(BP+0ECh)`.

### 6.2 Rendre un nombre

```asm
        pushu   x               ; bin2dec ECRASE X : le sauver
        mv      (BP+0),000H     ; positif, simple precision
        ; entier en (BP+1)..(BP+3)
        callf   bin2dec         ; 0EFB6Fh -> nombre BASIC en (BP+0)..(BP+14)
        popu    x
        rc
        retf
```

| | |
|---|---|
| ✅ `bin2dec` `0EFB6Fh` | convertit l'entier de `(BP+0)`..`(BP+3)` en nombre BASIC, **dans le même cadre** |
| ⚠️ 20 bits | ne convertit que **8 + 8 + 4** bits (`0EFB8Bh`) : un quartet haut non nul est **perdu en silence** (`&345678` revient `&045678`, mesuré). Refuser plutôt que tronquer (erreur 33) |
| ⛔ `X` | **écrasé** par `bin2dec` : `pushu x`/`popu x` autour de l'appel. Oublié dans la première version d'`INSTR` |

### 6.3 Rendre une chaîne

```asm
; U = base du resultat, IL = longueur ; BP au cadre d'UN SEUL eval
ret_str:
        mv      (BP+0),080H     ; type chaine
        mv      (BP+1),u        ; adresse (3 octets)
        mv      (BP+4),il       ; longueur
        rc
        retf
```

⛔ **Le résultat doit REMPLACER l'argument sur `U`, sans laisser de trou.** Sinon la
concaténation `"["+TRIM$(...)` lit par-dessus le trou et corrompt `"["`. Trois cas, tous
éprouvés :

| Cas | Conduite | Exemple |
|---|---|---|
| même longueur | transformer **sur place** | `UCASE$`, `LCASE$` |
| plus court | copier la sous-plage **au sommet** de la zone de l'argument (du haut vers le bas), puis remonter `U` | `TRIM$`, `LTRIM$`, `RTRIM$` ; `LEFT$` fait de même (`0FD7C7h`–`0FD7D1h`) |
| plus long | **réserver** la différence par `alloc`, puis remplir de façon que le résultat finisse où finissait l'argument | `REPT$`, `SREPT$` |

**`alloc`** `0EF0DDh` (`CHKROOM` dans `Routines-ROM-PC-E500S.asm`) : ✅ réserve `BA` octets sous
`U` (`sub u,ba`). 📖 Il refuse si `[s1_btm] + 1Eh + BA ≥ U` : `A` = `36h`, **erreur 54**
*Buffer space exceeded*, retenue armée. Il préserve `X`.

### 6.4 Rendre un nombre calculé sur des chaînes

Une fonction qui **lit** des chaînes et **rend** un nombre (`LEN`, `ASC`, `INSTR`) doit **libérer**
les chaînes temporaires de `U` avant de rendre le nombre :

```asm
        mv      a,(BP+4)        ; longueur de la derniere chaine lue
        add     u,a             ; comme BAS_LEN en 0EECB2h
```

📖 La ROM a un service pour cela, **`0EF100h`** : si `(BP+0)` désigne une chaîne, il fait
`add u,(BP+4)`, **puis rend le cadre** (`jp 0ECB5Dh`, soit `pmdf +15` / `ret`), en préservant `A`
(`mv b,a` … `mv a,b`). Lu, non employé par BASEXT, non éprouvé.

### 6.5 Rendre une instruction

`X` avancé au-delà de tout ce qui a été consommé, le caractère non attendu **remis** (`dec x`),
`BP` inchangé, `rc` / `retf`.

### 6.6 Signaler une erreur

```asm
        mv      (bp_ram),[!sv_bp0]      ; BP d'entree
        mv      a,<code>                ; code BASIC
        sc
        retf
```

C'est la forme de la ROM elle-même (`0F5960h` : `mv a,00Ah` / `sc` / `retf`). L'interpréteur
affiche le message et le numéro de ligne.

✅ **Rendre l'état d'avant l'appel** est la politique de la ROM : `0ECD63h` rend `+15` avant de
signaler l'erreur 21, `0F5C74h` rend `+15` avant l'erreur 33.

| Code | Message | Employé par la ROM en |
|---|---|---|
| `0Ah` = **10** | *Syntax error* | `0F5960h`, `0FD619h` |
| `15h` = **21** | *Division by zero* | `0ECD67h` |
| `16h` = **22** | *Illegal function call* | `0EF28Dh` (échec de `eval` sans code) |
| `21h` = **33** | *Data out of range* | `0EFB16h` (`dec2bin`), `0F5C74h` |
| `36h` = **54** | *Buffer space exceeded* | `0EF0FCh` (`alloc`) |
| `5Ah` = **90** | *Type mismatch* | `0EFC04h` (`chknum`), `0FC62Eh` (lecteur de `LEFT$`) |

La liste des 50 messages est dans `SC62015Disassembler/Data/BasicErrors.csv`.

---

## 7. Les adresses de la ROM — référentiel

### 7.1 Services appelables depuis une extension (entrée finissant par `retf`)

| Adresse | Nom | Rôle | Statut |
|---|---|---|---|
| `0EFBF3h` | `chknum` | évalue **un terme**, exige un nombre (erreur 90), cadre −15 | ✅ machine |
| `0EF26Eh` | `eval` | évalue **une expression**, numérique ou chaîne ; type non vérifié ; cadre −15 | ✅ machine |
| `0EFAD4h` | `dec2bin` | nombre → entier `(BP+1)..(BP+3)`, signe en bit 3 de `(BP+0)`, refus ≥ 2²⁰ (33) | ✅ machine |
| `0EFB6Fh` | `bin2dec` | entier `(BP+0)..(BP+3)` → nombre ; **20 bits** ; **écrase `X`** | ✅ machine |
| `0EF0DDh` | `alloc` (`CHKROOM`) | réserve `BA` octets sous `U` ; erreur 54 | ✅ machine (`REPT$`, `SREPT$`) |
| `0EF100h` | — | libère la chaîne du cadre de `U` et rend le cadre | 📖 lu |
| `0FFFE8h` | `iocs_call` | la porte du **device 9** (bibliothèque mathématique) : `mvw (cl),00009h` / `mv il,<cmd>` / `callf iocs_call` | ✅ machine (`Samples/DEVICE9`) — contrat complet dans `12-extensions-basic.md` §13 |

⚠️ `dec2bin` et `bin2dec` sont aussi les commandes `07Eh` et `07Fh` du device 9, mais appelées
**directement** ici : c'est la route éprouvée par BASEXT.

### 7.2 Le mécanisme de l'interpréteur (à connaître, pas à appeler)

| Adresse | Rôle |
|---|---|
| `0F4D9Dh` | index par lettre de la table des mots-clés |
| `0F4DD1h` | table token → nom (`LIST`) |
| `0F4FD1h` | table de répartition, 256 × 3 |
| `0F52DCh`–`0F570Ah` | table des mots-clés |
| `0F58D8h` | résolveur des instructions (test `080h` en `0F58E8h`) |
| `0F590Bh` | résolveur des fonctions (test `040h` en `0F591Bh`, `+3`) |
| `0F593Dh` | balayage de la table de répartition d'une extension |
| `0F5960h` | refus : erreur 10 |
| `0F93C3h` | pose la sentinelle `0FFFFFh` dans les deux crochets |
| `0F98C9h` | recopie `[0BFD0Eh]` dans `basptr` |
| `0EF2C5h` | reconnaissance **câblée** des opérateurs `AND`/`OR`/`XOR` (§11) |

### 7.3 Routines modèles, à lire avant d'écrire

| Adresse | Modèle de | Ce qu'on y lit |
|---|---|---|
| `0F9F44h` `PEEK` | fonction numérique à un terme | `chknum`, conversion, `pushu x` **après** l'évaluation, `bin2dec` |
| `0F9EF2h` `POKE` | instruction à liste | la boucle `,`, le `dec x` de sortie, le bilan de `BP` |
| `0FD322h` `POINT`, lecteur `0FD5E7h` | fonction à arguments parenthésés | `(` `,` `)` vérifiés un à un |
| `0FC613h` | lecteur d'une chaîne | `eval` + test du bit 7 |
| `0FD747h` `LEFT$`, fin `0FD7D3h` | fonction chaîne | copie au sommet, descripteur, **pas de `pmdf`** |
| `0FD6BDh` `CHR$`, fin `0FD6F9h` | fonction chaîne sur argument numérique | le `pmdf −15` qui compense le `+15` de `0F5C58h` |
| `0EECA8h` `LEN` | nombre rendu depuis une chaîne | libération de `U` |
| `0F5C58h`, `0F5C9Ah` | enveloppes de conversion | bornes, erreurs 33, `pmdf +15` |
| `0FB2D9h` | saut des espaces | regarde sans consommer |

### 7.4 Mémoire et système

| Adresse | Nom | |
|---|---|---|
| `0D1h` (RAM interne) | `basptr` | pointeur de la zone de travail du BASIC ; crochets en `+090h` et `+093h` |
| `0ECh` (RAM interne) | `bp_ram` | `BP` |
| `0BFD0Eh` | `baswrk` | **contient** le pointeur, recopié dans `basptr` |
| `0BFD1Ah` | `usrwrk` | **pointeur** (3 octets) vers le début de la zone langage machine ; ⛔ ce n'est pas une adresse de chargement |
| `0BFC00h` | — | début de la System Data Area : **plafond** de la zone langage machine |
| `0BFE03h` + `CALL &FFFD8` | `secure_work_call` | réservation de la zone (§9.2) |

---

## 8. Gabarits de code

Extraits de `src/BASEXT.ASM`, **validé sur machine**. En-tête commun :

```asm
        include pce500.inc
chknum:   equ   0EFBF3H
dec2bin:  equ   0EFAD4H
bin2dec:  equ   0EFB6FH
eval:     equ   0EF26EH
alloc:    equ   0EF0DDH
        org     0BF000H
        pre_on                  ; INDISPENSABLE : sans PRE, (n) est (BP+n)
```

⛔ **Sous `pre_on`, écrire `(BP+n)`, jamais `(000H)`** : `(000H)` y désigne l'adresse **directe** 0.
Le mode `(BP+n)` est celui qui n'émet **pas** d'octet PRE ; la vérification se fait dans l'objet.

### 8.1 Fonction numérique à un terme — `LPEEK adr`

```asm
lpeek_m3:
        db      0,0,0           ; les trois octets que le resolveur saute
lpeek:
        callf   chknum          ; -> cadre -15, nombre en (BP+0)
        jrc     dehors          ; X pas encore sauve : rien a rendre
        callf   dec2bin         ; -> (BP+1)..(BP+3) ; en echec, cadre deja rendu
        jrc     dehors
        mv      a,(BP+0)
        test    a,008H          ; negatif ?
        jrnz    refus
        mv      a,(BP+3)
        cmp     a,010H          ; adresse au-dela de 0FFFFFh ?
        jrnc    refus
        pushu   x               ; APRES l'evaluation
        mv      y,(BP+1)
        mvp     (BP+1),[y]      ; le travail, DANS le cadre du resultat
        mv      a,(BP+3)
        and     a,0F0H          ; bin2dec perdrait ce quartet
        jrnz    hors_plage
        mv      (BP+0),000H
        callf   bin2dec
        rc
        popu    x
dehors: retf
refus:
        pmdf    (bp_ram),00FH   ; rendre le cadre de chknum
        mv      a,00AH          ; 10
        sc
        retf
hors_plage:
        popu    x
        pmdf    (bp_ram),00FH
        mv      a,021H          ; 33
        sc
        retf
```

### 8.2 Fonction à deux arguments parenthésés — `MOD (a,b)` (lecture)

```asm
modu_m3: db     0,0,0
modu:
md_sp:  mv      a,[x++]
        cmp     a,020H          ; espaces
        jrz     md_sp
        cmp     a,028H          ; '(' consommee ICI
        jrnz    md_syn0         ; -> dec x / erreur 10
        mv      [!sv_bp0],(bp_ram)
        callf   eval            ; 1er argument
        jrc     md_ret
        test    (BP+0),080H     ; chaine ?
        jrnz    md_type         ; -> erreur 90
        mv      [!sv_bp1],(bp_ram)
        callf   dec2bin
        jrc     md_ret
        test    (BP+0),008H     ; signe
        jrnz    md_neg          ; -> erreur 33
        mvp     [!sv_a],(BP+1)  ; A a l'abri AVANT le 2e eval
        mv      a,[x++]
        cmp     a,02CH          ; ','
        jrnz    md_syn
        callf   eval            ; 2e argument
        ...                     ; memes controles
        mv      a,[x++]
        cmp     a,029H          ; ')'
        jrnz    md_syn
        ...                     ; calcul
        mv      (bp_ram),[!sv_bp1]      ; cadre du resultat, en absolu
        mv      (BP+0),000H
        mvp     (BP+1),[!sv_a]
        callf   bin2dec
        popu    x
        rc
md_ret: retf
```

### 8.3 Fonction chaîne — `UCASE$ (s$)`

```asm
rd1str:                         ; '(' chaine ')' ; APPEL PROCHE
rd_sp:  mv      a,[x++]
        cmp     a,020H
        jrz     rd_sp
        cmp     a,028H
        jrz     rd_ev
        dec     x
        mv      a,00AH
        sc
        ret
rd_ev:  mv      [!sv_bp0],(bp_ram)
        callf   eval
        jrc     rd_er
        test    (BP+0),080H
        jrz     rd_ty           ; pas une chaine -> 90
        mv      a,[x++]
        cmp     a,029H
        jrz     rd_ok
        mv      (bp_ram),[!sv_bp0]
        mv      a,00AH
        sc
        ret
rd_ty:  mv      (bp_ram),[!sv_bp0]
        mv      a,05AH
        sc
        ret
rd_ok:  rc
        ret
rd_er:  ret

ucase_m3: db    0,0,0
ucase:  call    rd1str
        jrc     st_err
        mv      y,u             ; la chaine est a U
        mv      il,(BP+4)
        ...                     ; transformation SUR PLACE
        mv      il,(BP+4)
        jp      ret_str         ; §6.3 -- aucun pmdf
st_err: retf
```

### 8.4 Instruction à liste — `LPOKE dest,v1,v2,...`

```asm
lpoke:                          ; instruction : PAS de prefixe de 3 octets
        callf   chknum          ; destination
        jrc     lp_ret
        callf   dec2bin
        jrc     lp_ret
        ...                     ; controles de signe et de borne
        mv      y,(BP+1)
        pmdf    (bp_ram),00FH   ; rendre le cadre de la destination
lp_next:
        mv      a,[x++]
        cmp     a,02CH
        jrnz    lp_done
        pushu   y
        callf   chknum          ; une valeur
        jrc     lp_pop
        callf   dec2bin
        jrc     lp_pop
        ...
        popu    y
        mvp     [y],(BP+1)
        mv      a,003H
        add     y,a
        pmdf    (bp_ram),00FH   ; rendre le cadre de CHAQUE valeur
        jr      lp_next
lp_done:
        rc                      ; tombe dans dec x, comme BAS_POKE
lp_back:
        dec     x               ; remettre le caractere qui n'etait pas ','
lp_ret: retf
lp_pop: popu    y               ; chknum/dec2bin en echec : cadre deja rendu
        retf
```

---

## 9. Mise en œuvre sur la machine

### 9.1 Assembler et vérifier l'objet

```powershell
cd C:\Claude\BASEXT\src
C:\Claude\xasm2026-4\bin\xasm2026-4.exe BASEXT.ASM -O -L -S -B -K
```

`-B` produit le `.UU`, un programme BASIC auto-décodeur qui recrée l'objet sur la machine. `-K`
allège le listing des constantes inutilisées de `pce500.inc`.

Dans le `.lst`, contrôler :

| Ligne | Octets attendus |
|---|---|
| `mv x,(basptr)` | `30 84 D1` (et **pas** `30 84 0E`) |
| `mv a,(BP+0)` | **sans** PRE : `80 00` |
| `mv [!sv_bp1],(bp_ram)` | **avec** PRE : `30 D8 …` |
| `cmp (BP+n),a` | `63 nn` ✅ ; ⛔ `cmp a,(n)` n'existe pas (voir §10) |

⚠️ **Nom de fichier en 8.3**, extension comprise, et en **MAJUSCULES** (`BASEXT.OBJ`) : la
machine refuse un nom trop long.

### 9.2 Réserver la zone langage machine

Un module chargé en `0BF000h` **n'est pas protégé** par défaut. ✅ Constaté sur machine : le texte
BASIC tapé ensuite (`MYADR = PEEK`) a été écrit un octet après la fin du module.

```basic
POKE &BFE03,&1A,&FD,&B,0,&C,0 : CALL &FFFD8
```

réserve **`0C00h` = 3072 octets**, soit une zone de `0BF000h` à `0BFC00h`.

⛔ **`0BFC00h` est un plafond, pas une base** : une taille calculée depuis `&BFE00` vaut −512 et
ne protège rien. ✅ VOGUE (N. Kon, 1992) réserve sa zone par la même porte.

⚠️ `CALL &FFFD8` provoque un **petit reset**. ✅ Mesuré le 2026-09-16 avec `C:\Claude\BASEXT-DRV` :
il **conserve** les deux crochets et le maillon de la chaîne IOCS (§12, point 3). Ce qu'il met en
jeu n'est donc pas l'installation, c'est la **protection** du code : un module en `0BF000h` reste
sûr tant que la nouvelle réservation le couvre. À la première installation la question ne se pose
pas — le module se charge **après** la réservation ; après avoir réduit la zone, vérifier qu'elle
couvre encore le module avant de se servir de ses mots-clés.

### 9.3 L'ordre, qui n'est pas négociable

1. réserver la zone (§9.2) ;
2. charger l'objet : `LOAD M "S1:BASEXT.OBJ"` ;
3. installer : `CALL &BF000` ;
4. **vérifier** (§3.4) ;
5. **puis seulement** charger ou saisir le programme qui emploie les mots-clés.

⛔ Un programme saisi avant l'installation garde `MOD (17,5)` comme **référence de tableau** :
*Array specified without DIM*. Cela vaut pour tout `.BAS` **ré-importé**. Un `.BSA` déjà tokenisé
garde son token.

⛔ **Fichiers `.BAS` pour la machine** : fins de ligne **CRLF** (un LF seul donne *Line buffer
overflow*) et **MAJUSCULES ASCII** (les minuscules sont mangées à l'import).

⛔ **Pas de guillemet doublé dans une chaîne.** `PRINT "SET ""S1:X.SYS"""` — l'échappement
des BASIC Microsoft — est **refusé** par ce BASIC : il faut `CHR$ 34`. La forme qui passe :

```basic
300 PRINT "OTER : SET ";CHR$ 34;"S1:T48.SYS";CHR$ 34;",";CHR$ 34;" ";CHR$ 34
```

⚠️ `""` **seul** reste la chaîne vide, et il est parfaitement valable : `N$=""`,
`IF INKEY$ ="" THEN …`. Ce qui est refusé, c'est le guillemet doublé **à l'intérieur** d'une
chaîne non vide. Relevé par J.-F. Albouy le 2026-09-26, sur six lignes de programmes d'essai.

### 9.4 Éprouver

Un essai n'est complet que s'il couvre **chaque refus** avec son code, et si le BASIC contrôle
lui-même le résultat sur un grand nombre de valeurs (`MODTEST.BAS` : 40 contrôles contre
`I*3571-997*INT (I*3571/997)`, sans un écart).

| Symptôme | Ce qu'il désigne |
|---|---|
| `0` pour **toutes** les valeurs | un opérande perdu ou un calcul qui ne calcule pas, jamais un cas particulier |
| *Syntax error* sans autre indice | `X` non rendu, ou ponctuation laissée à l'évaluateur |
| la machine revient au MENU | désynchronisation du code (instruction mal encodée) ou `BP` corrompu |
| *Array specified without DIM* | programme tokenisé avant l'installation |
| `OFF` qui plante après quelques commandes | `BP` qui dérive d'un cadre par appel |

**Méthode** : poser des **témoins** en RAM du module (`mvp [!dbg],(BP+n)`) et les relire au
`LPEEK` ; vider la plage du module dans un fichier et le comparer au `.lst` **de la bonne
version** (`12-extensions-basic.md` §15).

---

## 10. Catalogue des pièges

Tous ont coûté au moins une séance.

| Piège | Règle | Réf. |
|---|---|---|
| ⛔ nom préfixé | ni préfixe ni début d'un mot-clé existant | §1.2 |
| ⛔ `baswrk` pour `basptr` | `30 84 D1` dans l'objet | §3.1 |
| ⛔ `(000H)` sous `pre_on` | écrire `(BP+n)` | §8 |
| ⛔ service en `ret` | l'entrée en `retf` | §4 |
| ⛔ `X` sauvé avant l'évaluation | `pushu x` **après** `chknum`/`eval` | §4, §8.1 |
| ⛔ `X` écrasé par `bin2dec` | `pushu x`/`popu x` autour | §6.2 |
| ⛔ parenthèse laissée à l'évaluateur | la consommer soi-même | §5.3 |
| ⛔ `chknum` pour une expression | `eval` dès qu'il y a des parenthèses | §5.1 |
| ⚠️ `eval` ne vérifie pas le type | tester le bit 7 de `(BP+0)` | §5.1 |
| ⚠️ `dec2bin` en échec a déjà rendu son cadre | ne rien rendre de plus | §5.2 |
| ⛔ cadre de `chknum` non rendu dans une boucle | `pmdf +15` par valeur | §8.4 |
| ⛔ `pmdf −15` « indispensable » pour une chaîne | compter le **net** : −15 | §6.1 |
| ⛔ résultat chaîne qui laisse un trou | remplacer l'argument sur `U` | §6.3 |
| ⛔ `mv` pour deux octets | `mv` 1, `mvw` 2, `mvp` 3 | `JOURNAL` (`WPEEK`) |
| ⛔ `rol`/`ror` pour un décalage multi-octets | ils sont **circulaires dans l'octet** : `shl`/`shr` | `12-extensions-basic.md` §11 |
| ⛔ `cmp a,(n)` | n'existe pas ; écrire `cmp (n),a` (opérandes et retenue inversés). `xasm2026-4` l'acceptait et l'encodait en `62h` (5 octets) : corrigé et verrouillé par un test le 2026-09-15 | `xasm2026-4/RAPPORT-BUG-cmp-a-parentheses.md` |
| ⚠️ valeurs ≥ 2²⁰ | refusées par `dec2bin`, tronquées par `bin2dec` | §5.2, §6.2 |
| ⛔ appel d'un diviseur du device 9 par zéro | `BP` +30 en silence : **tester le diviseur soi-même** | `12-extensions-basic.md` §16 |
| ⛔ installation répétée | test de sentinelle | §3.3 |
| ⛔ zone non réservée | §9.2 | §9.2 |
| ⛔ programme saisi avant l'installation | §9.3 | §9.3 |
| ⛔ nom de fichier de plus de 8 caractères | 8.3, majuscules | §9.1 |
| ⛔ essai qui écrit dans le module | un `LPOKE`/`POKE` d'essai doit viser une adresse **au-delà de la fin du module**, relue dans le `.lst` à chaque version. Mesuré le 2026-09-16 : `BEXTTEST.BAS` écrivait en `&BF800`, libre à 1740 octets mais **dans `xf_pre`** à 2709 ; le filtre exécutait les octets écrits et la machine perdait ses lecteurs (`S1:`/`S2:` NEW CARD). `TEST.BAS` et `BEXT.BAS` (`&BF300`) avaient le même défaut. Les trois visent désormais `&BFBF0` | `essais/` |
| ⛔ filtre de l'écran chaîné dans `d_link` | le FCS **mémorise l'entrée du pilote à l'ouverture** (`0E07F1h`) et saute à `[bloc+2]` (`0E0907h`) sans passer par `iocs_call` : un `PRINT` ne voit jamais la chaîne. Remplacer l'adresse dans le bloc de contrôle du handle (relevé sur `s1-1.bin` : `00 00 E7 21 0F A2`) ✅ machine | `src/BASEXT.ASM`, filtre de `XCONSOLE` |

---

## 11. Limites du mécanisme

- ⛔ **Pas d'opérateur infixe.** `A MOD B` est hors d'atteinte : l'analyseur d'expression
  reconnaît `AND`, `OR`, `XOR` par trois comparaisons littérales (`cmp a,0A1h` / `0A2h` / `0A5h`
  en `0EF2CDh`–`0EF2D5h`), sans table ni plage. Un opérateur se réalise en **fonction à deux
  arguments**, sur le modèle de `POINT (x,y)`.
- ⛔ **Une seule extension à la fois.** Chaque crochet porte **un** pointeur, et le balayage
  s'arrête au premier `00`. Un second module écrase le premier : d'où un module unique,
  BASEXT, qui regroupe les douze mots-clés.
- ⚠️ **Entiers de 20 bits** pour tout ce qui passe par `dec2bin`/`bin2dec`. Le domaine complet du
  BASIC (flottants, 10 ou 20 chiffres) passe par le device 9 (§7.1).
- ⚠️ **Le module doit tenir dans la zone réservée.** BASEXT fait 2709 octets (`0BF000h`–`0BFA94h`)
  sur 3072, depuis l'ajout de `XCONSOLE`, `XCLS` et du filtre d'écriture (1740 octets auparavant).

---

## 12. Points ouverts

| # | Question | Pour la trancher |
|---|---|---|
| 1 | ✅ **Clos** — `BEXTTEST.BAS` ligne 60 écrivait `LPOKE &BF800,&123456,&789ABC`, deux valeurs au-delà de `0FFFFFh`. **L'erreur 33 a été vérifiée sur émulateur** par J.-F. Albouy le 2026-09-15, comme le prédisait le code de `dec2bin`. Corrigé en `&12345,&6789A` : attendu `LPEEK = 12345 6789A`, puis `WPEEK = 2345` | — |
| 2 | ✅ **Clos pour le mécanisme** — rendre les crochets depuis `old_kw`/`old_disp` **fonctionne** : éprouvé sur émulateur le 2026-09-16 par J.-F. Albouy avec `C:\Claude\BASEXT-DRV` (routine `bd_arret` du pilote, qui ne les rend que s'ils désignent encore `kw_table`) : crochet des noms relu **`FFFFF`** après désinstallation. ⚠️ Le module autonome, lui, n'a toujours **pas** d'entrée de désinstallation | écrire l'entrée dans le module autonome, sur le modèle de `bd_arret` |
| 3 | ✅ **Clos pour les gestes courants** — avec BASEXT résident (`BASEXT-DRV`, 2026-09-16), les crochets **survivent** à `OFF`/`ON`, au petit reset `CALL &FFFD8` (zone ramenée à 16 octets, puis à 0) et au **soft RESET** (bouton RESET seul, sans confirmation d'initialisation), rapportés par J.-F. Albouy (`DRVTEST.BAS` : `CROCHETS : OK`). ⚠️ Reste à savoir quel chemin exécute `0F93C3h` (la sentinelle) et `0F0D9Eh` (remise à zéro de `d_link`) : vraisemblablement l'initialisation de la mémoire | lire les appelants de `0F93C3h` |
| 4 | Le **chaînage** de deux modules | un module qui balaie d'abord la table sauvée |
| 5 | Un token d'extension **à la fois instruction et fonction** (drapeau `0C0h`) | reproduire le trampoline des six tokens doubles |
| 6 | 📖 Une fonction d'extension sur un token **d'instruction de la ROM** : la lecture des résolveurs le permettrait (la ROM ne porte pas le bit `040h`, le résolveur passe à l'extension), mais le nom se tokenise d'abord par la table de la ROM | essai |
| 7 | Les tokens `1Eh`, `1Fh`, `FEh`, `FFh` | essai (§2.3) |
| 8 | Trois arguments ou plus | lire `MID$` (`0FD75Ah`) : `0FC613h`, puis deux `0FD7E7h` séparés par `,` |
| 9 | Le cadre de `STR$` (`0FD6CDh`) : `0FC13Ch` n'a pas été lu, le bilan de `BP` n'est donc pas établi pour ce chemin | lire `0FC13Ch` |
| 10 | Un **`.BSA`** d'essai, qui échapperait au piège de la tokenisation | vérifier que `Sharp Basic Converter` accepte un token hors des 168 |

---

## 13. Sources

- **`Nx commandes BASIC.docx`** (documentation personnelle, non redistribuée) —
  traduction française d'un document allemand : les deux crochets, le format des deux listes, les
  bits 7 et 6, `RETF`, la retenue, `(BP+0)`, `X`. La spécification d'origine.
- **`rom83.bin`** (`SC62015Disassembler/Docs/ROM/`), désassemblée par `e500dasm` : toutes les
  adresses marquées 📖 ou lues, dont celles vérifiées pour ce document le 2026-09-15 (`0F58D8h`,
  `0F590Bh`, `0F593Dh`, `0F5960h`, `0F93C3h`, `0F98C9h`, `0EFBF3h`, `0EF26Eh`, `0EFAD4h`,
  `0EF0DDh`, `0EF100h`, `0EECA8h`, `0F5C58h`, `0F5C9Ah`, `0F5F4Fh`–`0F5FA5h`, `0F9EF2h`, `0F9F44h`,
  `0FB2D9h`, `0FC613h`, `0FD5E7h`, `0FD6BDh`–`0FD705h`, `0FD747h`–`0FD7E5h`).
- **`outils/extraire_tokens.py`** → `donnees/tokens-rom83.csv` : la table du §2, recoupée avec
  **`SC62015Disassembler/Data/BasicTokens.csv`** (relevés `BASIC500S.DAT`, J.-F. Albouy).
- **`SC62015Disassembler/Docs/Synthese/BASIC-en-ROM.md`** — les quatre tables, les trampolines,
  le moule de 15 octets (§9), BASCOM.
- **`SC62015Disassembler/Docs/Routines-ROM-PC-E500S.asm`** — noms `CHKROOM`, `CHKTYPE`, et la
  section des extensions.
- **`Referentiel PC-E500S SC62015/12-extensions-basic.md`** — le référentiel historique : les
  mesures de cadre, le device 9, les matrices, la méthode.
- **`JOURNAL-MISE-AU-POINT.md`** — le journal de BASEXT (ex-README de
  `SC62015Disassembler/Samples/BASEXT`), avec ses corrections en tête.
- **Mesures sur PC-E500S et PockEmul**, septembre 2026 (J.-F. Albouy) : `LPEEK`, `WPEEK`, `LPOKE`
  (2026-09-03/04), `MOD` (2026-09-05), convention chaîne (2026-09-14), douze mots-clés
  (2026-09-15).
- **`SC62015Disassembler/Data/BasicErrors.csv`** — les 50 messages (manuel `PC-E500S-DE.pdf`,
  annexe A).
- **BASCOM** (TORO, 1994), `SC62015Disassembler/Samples/BASCOM/` — seul exemple tiers du mécanisme.

---

*Rédigé le 2026-09-15 à partir des sources ci-dessus. La table du §2 se régénère par
`python outils/extraire_tokens.py` ; toute autre adresse se vérifie avec
`e500dasm rom83.bin --format rom --base C0000h --mode flow --range <début>h:<fin>h`.*
