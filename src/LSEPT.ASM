; ============================================================================
; LPEEK.ASM -- ajoute la FONCTION BASIC  LPEEK <adresse>
; ============================================================================
;
; ⛔ LE NOM NE POUVAIT PAS ETRE "PEEKX", ET L'ESSAI MACHINE L'A MONTRE.
;    Le tokeniseur consulte la table de la ROM AVANT la notre. "PEEKX" y est
;    donc coupe en PEEK + la variable X, et la ligne devient une erreur de
;    syntaxe -- relue ensuite, elle s'affiche litteralement
;    "PRINT HEX$ PEEK X &BF100".
;
;    LA REGLE, valable pour toute extension : un mot-cle ajoute ne doit pas
;    COMMENCER par un mot-cle existant, ni etre le debut de l'un d'eux. Cela se
;    verifie avant d'ecrire une ligne de code, sur les 168 noms de
;    Data/BasicTokens.csv. LPEEK est libre dans les deux sens.
;
;   LPEEK &BF0B8   rend la valeur de l'adresse 3 octets rangee en &BF0B8,
;                  soit l'equivalent de
;                  PEEK &BF0B8 + PEEK &BF0B9 * 256 + PEEK &BF0BA * 65536
;
; Ce n'est pas un CALL : c'est une INSTRUCTION DU LANGAGE, utilisable dans une
; expression -- PRINT LPEEK &BF0B8, A = LPEEK X + 1, etc.
;
;   LOAD M "S1:LPEEK.OBJ" : CALL &BF000      installe
;   PRINT HEX$ LPEEK &BF0B8
;
; ---------------------------------------------------------------------------
; COMMENT L'INTERPRETEUR NOUS TROUVE  (tout est lu dans la ROM)
; ---------------------------------------------------------------------------
;
; Deux crochets dans la zone de travail du BASIC, x = (baswrk) = (0D1h) :
;
;   [x+090h]   la table de mots-cles      (texte -> token)
;   [x+093h]   la table de repartition    (token -> routine)
;
; La ROM y met 0FFFFFh au demarrage (SUB_F93C3) : la sentinelle "rien".
;
; La repartition se balaie par SUB_F593D (0F593Dh) : entrees de QUATRE octets,
; token puis adresse, arret sur un token 000h.
;
; ⛔ ET LE QUARTET HAUT DU 3e OCTET D'ADRESSE EST UN DRAPEAU. Les deux
;    resolveurs de la ROM sont cote a cote et ne different que par le bit :
;
;      0F58E5h  instruction : test a,080h -> routine = l'adresse telle quelle
;      0F590Bh  FONCTION    : test a,040h -> routine = l'adresse + 3
;
;    PEEKX etant une fonction, on range donc (routine - 3) avec le bit 6 arme.
;    Les trois octets sautes n'ont aucun sens : dans la ROM, ce sont ceux de la
;    routine precedente. On y met trois zeros.
;
; ---------------------------------------------------------------------------
; LE CORPS -- calque sur BAS_PEEK (0F9F44h), avec les entrees LOINTAINES
; ---------------------------------------------------------------------------
;
; Une extension vit en page 0B, les services en 0E et 0F. Un service termine
; par RET ne se laisse PAS appeler d'ici : son retour depile 2 octets et reste
; dans SA page. Il faut donc, pour chaque service, l'entree qui finit par RETF.
;
;   BAS_PEEK fait            ici on fait              parce que
;   -----------------------  -----------------------  ------------------------
;   call SUB_F5F9C           callf 0EFBF3h            F5F9C finit par RET ;
;                            puis callf 0EFAD4h       EFBF3 et EFAD4 par RETF.
;                                                     F5F9C n'etait que
;                                                     "callf EFBF3 + call
;                                                     F5C9A", et F5C9A n'etait
;                                                     que "callf EFAD4 + mv y".
;   callf SUB_EFB6F          callf 0EFB6Fh            deja lointaine
;
; 0EFAD4h et 0EFB6Fh sont les commandes 07Eh et 07Fh du device 9 -- dec2bin et
; bin2dec. Le travail sur la bibliotheque mathematique sert directement ici.
;
; ⛔ LE CADRE BP -- ET J'AI D'ABORD MAL LU SUB_F5C9A.
;
;    Elle se termine par "jr LOC_F5C6F", que je n'avais pas suivi. Or LOC_F5C6F
;    fait "pmdf (bp_ram),00Fh" : BP + 15. Le compte, entree a sortie :
;
;      entree                          BP = B
;      callf chknum                    BP = B-15   <- le cadre de la valeur
;      SUB_F5C9A finit par +15         BP = B
;      BAS_PEEK fait -15               BP = B-15   <- ou il ecrit son resultat
;
;    Ici on n'appelle pas F5C9A, donc on n'a PAS le +15 : apres chknum, BP vaut
;    deja B-15, c'est-a-dire exactement le bon cadre. Il ne faut donc AUCUN
;    pmdf sur le chemin de succes. La premiere version gardait le -15 de
;    BAS_PEEK sans son +15 : elle ecrivait en B-30.
;
;    Sur le chemin d'ERREUR, en revanche, il faut le +15 : F5C9A le fait dans
;    tous les cas, y compris son erreur 33 (LOC_F5C74 saute a LOC_F5C6F).
;
; ⛔ ET ON ECRIT (BP+n), PAS (000H). Sous pre_on, "(000H)" designe l'adresse
;    DIRECTE 0 ; le mode (BP+n) est celui qui n'emet PAS d'octet PRE. Le
;    controle se fait dans l'OBJET : sur ces lignes, BAS_PEEK ne porte aucun
;    PRE (E0 05 01, CC 00 00, CD 02 00 00). Une premiere version de ce fichier
;    portait "30 80 00" -- un PRE, donc l'adresse directe : la fonction lisait
;    la RAM interne 0 au lieu du cadre de l'argument.
;
;       xasm2026-4 LPEEK.ASM -O -L -S -B -K
; ============================================================================

        include pce500.inc

; --- les entrees LOINTAINES de la ROM (toutes terminees par RETF) -----------
chknum:   equ   0EFBF3H    ; evalue l'expression numerique, verifie le type
dec2bin:  equ   0EFAD4H    ; le nombre -> entier 24 bits en (bp+1)..(bp+3)
bin2dec:  equ   0EFB6FH    ; l'entier de (bp+0)..(bp+3) -> nombre BASIC

token:    equ   007H       ; libre dans la table de la ROM (BASCOM occupe 04-06)

; ⛔ NE PAS ECRIRE « baswrk » ICI. C'est la ZONE de travail, en memoire EXTERNE
;    (0BFD0Eh) -- nom repris du listing de E. Kako, ou il est declare
;    « baswrk: equ 0bfd0eh ». Le pointeur qu'il nous faut est en RAM INTERNE, a
;    0D1h, que le carnet nommait « baswrk » lui aussi jusqu'au 2026-09-03 et
;    nomme desormais « basptr ». Depuis, pce500.inc EXPOSE les deux et le
;    generateur REFUSE une collision de noms : il n'y a plus d'equ local ici.
;    Et « mv x,(baswrk) » ne proteste pas : l'operande interne fait 8 bits, XASM
;    TRONQUE 0BFD0Eh en 0Eh. Le code ecrivait donc les crochets en
;    [(00Eh)+090h], et la table d'extension n'a jamais ete installee.
;    Verifiable dans l'objet : on doit lire « 30 84 D1 », pas « 30 84 0E ».
err_syn:  equ   00AH       ; erreur BASIC 10, Syntax error

        org     0BF000H
        pre_on

; ============================================================================
; L'INSTALLATION -- c'est ici que mene CALL &BF000
; ============================================================================
start:
        pushu   x               ; X porte le point de reprise de l'interpreteur
        pushu   i
        mv      x,(basptr)
        mv      y,[x+090H]      ; l'ancienne table de mots-cles
        mv      [old_kw],y      ;   sauvee : de quoi desinstaller
        mv      y,[x+093H]      ; l'ancienne table de repartition
        mv      [old_disp],y
        mv      y,kw_table
        mv      [x+090H],y
        mv      y,disp_table
        mv      [x+093H],y
        popu    i
        popu    x
        rc                      ; carry CLAIR : retour propre a BASIC
        retf

; ============================================================================
; LA FONCTION -- l'interpreteur y saute a lpeek_m3 + 3
; ============================================================================
lpeek_m3:
        db      0,0,0           ; les trois octets que le resolveur saute

lpeek:
; ---------------------------------------------------------------------------
; SONDE 3 -- declaree INSTRUCTION (bit 7), et ne fait rien.
;
; « PRINT LSEPT (5) » a rendu « Array specified without DIM » : en position
; d'EXPRESSION, l'interpreteur voit notre mot-cle comme un nom de VARIABLE.
; Le token n'y est donc pas resolu comme fonction.
;
; Cette sonde le declare en instruction -- bit 7 au lieu du bit 6, et la
; routine pointee DIRECTEMENT (pas d'adresse-3). Elle ne fait rien du tout.
;
;   « LSEPT » seul ne dit rien   -> toute la chaine d'extension fonctionne,
;                                   et SEUL le bit fonction reste a percer.
;   « LSEPT » erreur             -> le probleme est en amont, et il ne sert a
;                                   rien de chercher du cote des fonctions.
; ---------------------------------------------------------------------------
        rc                      ; pas d'erreur
        retf

; ============================================================================
; LES DEUX TABLES
; ============================================================================
kw_table:
        db      5,'LSEPT',token
        db      0                       ; fin de table

disp_table:
; token, puis l'adresse de la routine sur 3 octets, BIT 7 arme = "instruction".
; Pour une FONCTION ce serait (routine - 3) avec le bit 6 : 040h au lieu de 080h.
; L'entree obtenue, « 07 28 F0 8B », a exactement la forme de celles de BASCOM
; (« 04 BB DF 8B ») -- meme quartet 8.
        db      token
        db      lpeek
        db      lpeek/256
        db      lpeek/65536+080H
        db      0                       ; fin de table

; ============================================================================
; LES CROCHETS D'ORIGINE, pour desinstaller
; ============================================================================
old_kw:   db    0,0,0
old_disp: db    0,0,0

        end
