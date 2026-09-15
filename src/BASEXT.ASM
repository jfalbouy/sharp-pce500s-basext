; ============================================================================
; BASEXT.ASM -- le module d'extensions du BASIC
; ============================================================================
; ATTENTION : LES NOMS DE FICHIER SHARP SONT EN 8.3
;    Ce module s'est d'abord appele BASIC_EXT -- neuf caracteres, un de trop.
;    La regle vaut pour tout ce qui part sur le lecteur, .OBJ comme .UU :
;    LOAD M "S1:BASEXT.OBJ" ne pardonne pas un nom trop long.
; ============================================================================
;                 LPEEK (fonction, 3 octets), WPEEK (fonction, 2 octets)
;                 et LPOKE (INSTRUCTION, ecrit des valeurs de 3 octets)
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
;       xasm2026-4 BASEXT.ASM -O -L -S -B -K
; ============================================================================

        include pce500.inc

; --- les entrees LOINTAINES de la ROM (toutes terminees par RETF) -----------
chknum:   equ   0EFBF3H    ; evalue l'expression numerique, verifie le type
dec2bin:  equ   0EFAD4H    ; le nombre -> entier 24 bits en (bp+1)..(bp+3)
bin2dec:  equ   0EFB6FH    ; l'entier de (bp+0)..(bp+3) -> nombre BASIC

; ⛔ DEUX EVALUATEURS, ET ILS NE LISENT PAS LA MEME CHOSE.
;    chknum (0EFBF3h) ne lit qu'UN TERME : un nombre, une variable, un appel de
;    fonction, ou une expression entre parentheses -- mais il s'arrete au premier
;    OPERATEUR. C'est ce que PEEK emploie (0F5F9Ch), et c'est pourquoi
;    « PEEK &BFD1C*&100 » se lit « (PEEK &BFD1C)*&100 ».
;    eval (0EF26Eh) evalue une EXPRESSION COMPLETE, operateurs compris. C'est ce
;    qu'emploie POINT (x,y), via SUB_F5F65 en 0F5F65h -- et la reconnaissance des
;    operateurs AND/OR/XOR est cablee juste a cote, en 0EF2C5h. Douze sites de la
;    ROM l'appellent par « callf ».
;
;    MOD emprunte sa syntaxe a POINT : il lui faut donc le second, et LPEEK garde
;    le premier puisqu'il est calque sur PEEK. Mesure sur machine avant la
;    correction : MOD (17,5) et MOD (A,B) passaient, mais MOD (A+1,B) et
;    MOD (I*3571,997) rendaient une erreur -- chknum lisait « A », puis butait
;    sur le « + ».
;
;    ⚠️ eval ne signale PAS lui-meme le type : ses appelants de la ROM font le
;    « test (000h),080h » a sa suite (0F5F6Bh). On fait de meme.
eval:     equ   0EF26EH    ; expression numerique complete -> (bp+0)


tk_lp:    equ   007H       ; LPEEK -- libre dans la table de la ROM
tk_wp:    equ   00AH       ; WPEEK -- libre aussi (BASCOM occupe 04-06)
tk_lpo:   equ   00EH       ; LPOKE -- libre
tk_mod:   equ   00FH       ; MOD   -- libre
tk_uc:    equ   0C6H       ; UCASE$ (fonctions chaine ajoutees)
tk_lc:    equ   0C7H       ; LCASE$
tk_tr:    equ   0C3H       ; TRIM$
tk_lt:    equ   0C4H       ; LTRIM$
tk_rt:    equ   0C5H       ; RTRIM$
tk_rp:    equ   0C8H       ; REPT$
tk_sr:    equ   0C9H       ; SREPT$
tk_in:    equ   0C2H       ; INSTR (rend un NOMBRE)
tk_xc:    equ   0CAH       ; XCONSOLE (instruction) -- libre, hors BASCOM (CB-CE)
tk_xcl:   equ   0CFH       ; XCLS     (instruction) -- libre, hors BASCOM
fhandle:  equ   0BFC6DH    ; FHANDLE : handle -> numero de bloc de controle
                          ; (absent de pce500.inc ; lu par 0E06A1h)
alloc:    equ   0EF0DDH    ; reserve BA octets sur U (U -= BA) ; carry = erreur 54


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
err_range: equ  021H       ; erreur BASIC 33, Data out of range
err_type: equ   05AH       ; erreur BASIC 90, Type mismatch -- le code que
                          ; chknum emploie lui-meme (0EFC04h)
err_buf:  equ   036H       ; erreur BASIC 54, Buffer space exceeded
err_div:  equ   015H       ; erreur BASIC 21, Division by zero -- le code
                          ; que la ROM elle-meme emploie, lu en 0ECD67h

        org     0BF000H
        pre_on

; ============================================================================
; L'INSTALLATION -- c'est ici que mene CALL &BF000
; ============================================================================
start:
        pushu   x               ; X porte le point de reprise de l'interpreteur
        pushu   i
; ⚠️ Un filtre d'une version PRECEDENTE du module peut rester branche sur le
;    handle 0 (voir XCONSOLE) : ses adresses ne valent plus rien. On le
;    debranche avant tout, en rendant l'entree d'origine du pilote.
        call    xf_off
        mv      x,(basptr)

; ⛔ NE SAUVER LES CROCHETS QUE S'ILS SONT ENCORE CEUX DE LA ROM.
;    Une premiere version sauvait sans regarder : au SECOND CALL &BF000 elle
;    ecrasait old_kw et old_disp avec NOS PROPRES tables, et les valeurs
;    d'origine etaient perdues -- la desinstallation avec. Constate sur machine
;    le 2026-09-05 : le vidage montrait old_kw = 0BF1B1h et old_disp = 0BF1CCh,
;    c'est-a-dire kw_table et disp_table de ce module.
;
;    ⛔ ET LA RAISON N'EST PAS CELLE QUE J'AVAIS ECRITE. J'avais justifie le
;    test par « les tables du BASIC vivent en page 0F ». C'est faux : le crochet
;    ne pointe JAMAIS sur la table de la ROM. La ROM y ecrit une SENTINELLE,
;    0FFFFFh, et cela se lit en 0F93C3h :
;
;       mv  x,(basptr)
;       mv  y,0FFFFFh
;       mv  [x+090h],y
;       mv  [x+093h],y
;
;    L'octet de poids fort d'un crochet vierge vaut donc 0Fh, et le test le
;    reconnait -- mais ce qu'il reconnait est la sentinelle, pas une table. Une
;    extension, elle, vit en RAM, page 0B : son crochet ne peut pas valoir 0Fh.
;    Le test est donc juste, et il l'est desormais pour la bonne raison.
;
;    ⚠️ Il pourrait etre plus strict : comparer les TROIS octets a 0FFFFFh plutot
;    que le seul poids fort. En l'etat il accepterait n'importe quel 0Fxxxxh, ce
;    qu'aucune extension ne peut produire -- mais la ROM le pourrait un jour.
;
;    ⚠️ Et il n'y a PAS de chainage : un second module ecraserait le premier.
;    Refuser d'ecraser la sauvegarde est donc la seule conduite sensee.
        mv      a,[x+092H]      ; poids fort du crochet des mots-cles
        cmp     a,00FH          ; encore la table de la ROM ?
        jrnz    deja_ext        ; non : ne rien ecraser
        mv      y,[x+090H]      ; l'ancienne table de mots-cles
        mv      [old_kw],y      ;   sauvee : de quoi desinstaller
        mv      y,[x+093H]      ; l'ancienne table de repartition
        mv      [old_disp],y
deja_ext:
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
        callf   chknum          ; l'argument -> cadre pousse, nombre en (bp+0)
        jrc     dehors          ; X n'est pas encore sauve : rien a rendre
        callf   dec2bin         ; -> entier 24 bits en (bp+1)..(bp+3)
        jrc     dehors
        mv      a,(BP+0)        ; (bp+0) : bit 3 = signe
        test    a,008H
        jrnz    refus           ; adresse negative
        mv      a,(BP+3)        ; l'octet de poids fort du 24 bits
        cmp     a,010H
        jrnc    refus           ; au-dela de 0FFFFFh : hors de l'espace

; ⛔ X PORTE LE POINT DE REPRISE, ET bin2dec L'ECRASE.
;    chknum a fait AVANCER X au-dela de l'argument : c'est cette valeur-la que
;    l'interpreteur attend au retour. On la sauve donc APRES chknum, jamais
;    avant -- exactement ou BAS_PEEK place son pushu (0F9F49h).
;    L'oubli ne plante pas : le nom est reconnu, la fonction s'execute, et
;    l'interpreteur reprend n'importe ou -- "Syntax error" sans autre indice.
        pushu   x

        mv      y,(BP+1)        ; l'adresse demandee
        mvp     (BP+1),[y]      ; les TROIS octets a cette adresse

; ⛔ bin2dec NE CONVERTIT QUE 20 BITS, et c'est lu dans son code (0EFB8Bh) :
;    trois passes de decalage, 8 bits sur (bp+11), 8 sur (bp+12), puis
;    QUATRE seulement sur (bp+13) -- « mv (00Eh),004h ». 8+8+4 = 20. Le quartet
;    haut du troisieme octet est ignore par construction : c'est un convertisseur
;    d'ADRESSE, et une adresse fait 20 bits sur cette machine.
;    Mesure : &345678 revenait en &045678, sans que rien ne le signale.
;    On REFUSE donc plutot que de mentir -- une valeur fausse en silence est
;    pire qu'une erreur.
        mv      a,(BP+3)
        and     a,0F0H
        jrnz    hors_plage      ; quartet haut non nul : bin2dec le perdrait

        mv      (BP+0),000H     ; positif, simple precision
        callf   bin2dec         ; -> nombre BASIC en (bp+0)
        rc
        popu    x               ; rendre son point de reprise a l'interpreteur
dehors:
        retf

refus:
        pmdf    (bp_ram),00FH   ; +15 : rendre BP comme le fait SUB_F5C9A
        mv      a,err_syn
        sc
        retf

; La valeur lue depasse 20 bits : erreur 33, celle que SUB_F5C9A emploie pour
; le meme cas. X a ete sauve, il faut le rendre.
hors_plage:
        popu    x
        pmdf    (bp_ram),00FH
        mv      a,err_range
        sc
        retf

; ============================================================================
; LA SECONDE FONCTION -- WPEEK, deux octets au lieu de trois
; ============================================================================
; Meme structure exactement. Elle n'existe que pour eprouver l'ENCHAINEMENT :
; nos deux tables n'avaient jamais porte qu'une seule entree, donc ni le
; balayage de SUB_F593D (« add y,004h » en boucle) ni celui du tokeniseur
; n'etaient exerces. Deux entrees suffisent a les mettre en defaut s'ils le
; sont -- et a montrer qu'aucune adresse n'en ecrase une autre.
;
; WPEEK n'a pas besoin du garde-fou des 20 bits : deux octets tiennent
; toujours dedans.

wpeek_m3:
        db      0,0,0           ; les trois octets que le resolveur saute

wpeek:
        callf   chknum
        jrc     dehors2
        callf   dec2bin
        jrc     dehors2
        mv      a,(BP+0)
        test    a,008H
        jrnz    refus2
        mv      a,(BP+3)
        cmp     a,010H
        jrnc    refus2
        pushu   x
        mv      y,(BP+1)
; ⛔ mvw, PAS mv. Les trois largeurs sont mv (1 octet), mvw (2) et mvp (3) --
;    « mv » ne transfere QU'UN octet, et un commentaire disant « deux octets :
;    mv, pas mvp » ne le rend pas vrai. Mesure : WPEEK rendait F178 et F1B8,
;    l'octet bas juste et l'octet haut jamais ecrit, donc laisse a sa valeur
;    precedente -- F1 les deux fois.
        mvw     (BP+1),[y]      ; DEUX octets
        mv      (BP+3),000H     ; le troisieme reste nul
        mv      (BP+0),000H
        callf   bin2dec
        rc
        popu    x
dehors2:
        retf

refus2:
        pmdf    (bp_ram),00FH
        mv      a,err_syn
        sc
        retf

; ============================================================================
; L'INSTRUCTION LPOKE destination,valeur1,valeur2,...
; ============================================================================
; Ecrit chaque valeur sur TROIS octets, en ordre petit-boutien, a des adresses
; consecutives :
;
;   LPOKE &BF000,&123456,&789ABC   met 56 34 12 en &BF000
;                                  puis BC 9A 78 en &BF003
;
; C'est le pendant de LPEEK, et il comble un manque reel : ces pointeurs de
; trois octets se decomposaient jusqu'ici a la main, cote BASIC --
;   AH=INT (AD/&10000):AM=INT ((AD-AH*&10000)/&100):AL=AD-AH*&10000-AM*&100
;   POKE dest,AL,AM,AH
;
; ⛔ C'EST UNE INSTRUCTION, PAS UNE FONCTION. Le resolveur de la ROM n'est donc
;    pas le meme : 0F58E5h teste le bit 7 et prend l'adresse TELLE QUELLE, la ou
;    0F590Bh teste le bit 6 et ajoute 3. L'entree de repartition porte donc 080h
;    et il n'y a PAS de prefixe de trois octets devant le point d'entree.
;
; ⛔ LA BOUCLE EST CELLE DE BAS_POKE (0F9F27h), Y COMPRIS SA SORTIE.
;    On lit un caractere, on le compare a 02Ch ; si ce n'est pas une virgule, on
;    rend la main -- mais en REMETTANT le caractere par un « dec x ». La ROM le
;    fait par une chute : son « rc » de 0F9F2Fh tombe dans le « dec x » de
;    0F9F30h, partage avec le chemin d'erreur. On copie cette disposition.
;
; ⛔ ET CHAQUE chknum PREND UN CADRE DE 15 OCTETS, QU'IL FAUT RENDRE.
;    LPEEK n'appelle chknum qu'une fois et n'a donc jamais eu a s'en soucier.
;    Ici la boucle en appelle un par valeur : sans le « pmdf +15 » apres chacune,
;    les cadres s'empilent et BP finit par sortir de sa zone. Le compte doit
;    revenir a zero sur TOUS les chemins, erreurs comprises.
;
; ⛔ PORTEE DES VALEURS : 20 BITS, ET C'EST dec2bin QUI L'IMPOSE.
;    Son code (0EFB8Bh) ne convertit que 8+8+4 bits -- constate en ecrivant
;    LPEEK. Une valeur au-dela de 0FFFFFh serait donc tronquee AVANT de nous
;    parvenir, sans que rien ne le signale et sans que nous puissions le
;    detecter apres coup. Sans consequence pour l'usage vise, une adresse de
;    cette machine faisant 20 bits, mais cela doit etre dit.

lpoke:
        callf   chknum          ; l'adresse de destination
        jrc     lp_ret          ; chknum a echoue : il n'a pas pris de cadre
        callf   dec2bin
        jrc     lp_ret
        mv      a,(BP+0)        ; bit 3 = signe
        test    a,008H
        jrnz    lp_syn
        mv      a,(BP+3)
        cmp     a,010H
        jrnc    lp_syn          ; au-dela de 0FFFFFh
        mv      y,(BP+1)        ; Y = la destination
        pmdf    (bp_ram),00FH   ; rendre le cadre de la destination

lp_next:
        mv      a,[x++]
        cmp     a,02CH          ; ','
        jrnz    lp_done         ; plus de virgule : c'est fini
        pushu   y               ; la destination, que chknum n'a pas a connaitre
        callf   chknum          ; la valeur
        jrc     lp_pop
        callf   dec2bin
        jrc     lp_pop
        mv      a,(BP+0)
        test    a,008H
        jrnz    lp_popsyn       ; valeur negative
        popu    y
        mvp     [y],(BP+1)      ; les TROIS octets, petit-boutien
        mv      a,003H
        add     y,a             ; adresse suivante
        pmdf    (bp_ram),00FH   ; rendre le cadre de la valeur
        jr      lp_next

; --- sortie ----------------------------------------------------------------
; « rc » tombe dans « dec x » : la disposition de BAS_POKE, ou le chemin de
; succes et celui d'erreur partagent la remise en place du caractere.
lp_done:
        rc
lp_back:
        dec     x               ; rendre le caractere qui n'etait pas une virgule
lp_ret:
        retf

lp_syn:
        pmdf    (bp_ram),00FH
        mv      a,err_syn
        sc
        retf

; chknum ou dec2bin a echoue alors que Y etait empile : le depiler, et ne PAS
; rendre de cadre -- chknum n'en a pas pris.
lp_pop:
        popu    y
        retf

lp_popsyn:
        popu    y
        pmdf    (bp_ram),00FH
        mv      a,err_syn
        sc
        retf

; ============================================================================
; LA FONCTION MOD (A,B) -- le reste de la division entiere
; ============================================================================
; L'interpreteur y saute a modu_m3 + 3 : c'est une FONCTION (drapeau 040h).
;
;   PRINT MOD (17,5)      2
;   R = MOD (A,B)
;
; ⛔ PAS D'INFIXE POSSIBLE. « A MOD B » est hors d'atteinte : la reconnaissance
;    des operateurs est CABLEE EN DUR dans l'analyseur d'expression, en 0EF2C5h,
;    par trois comparaisons litterales contre 0A1h (AND), 0A2h (OR) et 0A5h
;    (XOR) -- ni table, ni plage, et nos deux crochets n'y donnent pas acces.
;    La syntaxe est donc celle de POINT (x,y), que la machine possede deja.
;
; ⛔ ET LE CALCUL N'EMPRUNTE RIEN A LA BIBLIOTHEQUE FLOTTANTE DE LA ROM. Deux
;    versions ont essaye de calculer A - B * INT (A/B) par les commandes du
;    device 9 ; les deux ont plante la machine (CLS puis MENU principal), et la
;    seconde alors meme que ses cinq adresses etaient JUSTES -- verifiees une a
;    une dans la table de repartition DB_EF078 du driver drv_function :
;
;      047h add 0ECBA9h   048h sub 0ECBB4h   049h mul 0ECBBFh
;      04Ah div 0ECBD8h   056h int 0EE4D5h
;
;    Ce que ces adresses ne disent pas, c'est le CONTRAT. Il y a deux diviseurs
;    (SUB_ECCEA et SUB_ECD85), l'entree 04Ah ne mene qu'au second, et le seul
;    appelant connu de la ROM -- l'evaluateur d'expression en 0E8559h -- fait
;    « mv i,0000Fh / exl (000h),(00Fh) » AVANT d'appeler : il ECHANGE X et Y,
;    ce que ne fait aucune des trois autres operations.
;
;    Le calcul est donc fait ici, en binaire, et ne s'appuie que sur des
;    primitives EPROUVEES SUR LA MACHINE par LPEEK et LPOKE : chknum, dec2bin,
;    bin2dec.
;
; ⛔ ET ON NE SUPPOSE RIEN DE CE QUE chknum FAIT DE BP. Une premiere version
;    binaire tenait pour acquis qu'un chknum EMPILE un cadre de 15 octets, donc
;    qu'apres le second appel le premier operande se lisait en (bp+16)..(bp+18).
;    Je l'avais deduit d'un enchainement de la ROM en 0ECBCAh -- une inference,
;    pas une mesure. LA MACHINE L'A DEMENTIE : elle rendait 0 pour toutes les
;    valeurs, ce qui est la signature d'un A perdu (0 mod B, ou B mod B).
;
;    Plutot que de deviner une troisieme fois la taille et le sens du cadre,
;    cette version REND LA QUESTION SANS OBJET :
;      . le premier operande est mis a l'abri en RAM du module (sv_a) des que
;        dec2bin l'a converti, donc avant que le second chknum ne puisse rien
;        ecraser ;
;      . BP est SAUVE et RESTAURE en absolu (sv_bp0, sv_bp1) au lieu d'etre
;        rattrape par des pmdf comptes a la main.
;    Le module se comporte alors exactement comme LPEEK, qui lui fonctionne :
;    resultat en (bp+0)..(bp+3), BP tel qu'il etait apres LE PREMIER chknum.
;    Que chknum empile 15 octets, 8, ou rien du tout, le resultat est le meme.
;
; LE DOMAINE : A et B sont des ENTIERS de 0 a 1048575, celui de LPEEK et de
; LPOKE. La borne n'est pas un choix mais une mesure : dec2bin accumule dans X,
; registre de 20 bits, et REFUSE lui-meme au-dela (« add x,a / jrc » en
; 0EFAFBh, puis erreur 33) -- c'est donc la ROM, et non nous, qui signale un
; operande trop grand. Un operande negatif est refuse ici : dec2bin en rend la
; valeur absolue en laissant le signe dans le bit 3 de (bp+0), donc l'ignorer
; rendrait un resultat faux en silence. Le reste etant toujours < B, il tient
; toujours dans les 20 bits que bin2dec sait reconvertir.

modu_m3:
        db      0,0,0           ; les trois octets que le resolveur saute

modu:
; ⛔ LES PARENTHESES SONT OBLIGATOIRES, ET C'EST LA ROM QUI LE DIT.
;    SUB_FD5E7, le lecteur d'arguments de POINT (x,y), exige TROIS caracteres :
;    '(' en 0FD5ECh, ',' en 0FD5F9h et ')' en 0FD60Ah. Une premiere version de
;    cette fonction n'en verifiait qu'un : chknum recevait (17,5) tout entier et
;    tentait d'evaluer une expression parenthesee. PRINT MOD(17,5) repondait
;    Syntax error. Constate sur emulateur, corrige en relisant SUB_FD5E7.
md_sp:
        mv      a,[x++]
        cmp     a,020H          ; sauter les espaces -- ce que fait SUB_FB2D9
        jrz     md_sp
        cmp     a,028H          ; '(' obligatoire
        jrnz    md_syn0

; BP a l'entree : l'etat a rendre si l'on doit signaler une erreur, puisque
; c'est celui d'avant tout ce que nous avons pu prendre.
        mv      [!sv_bp0],(bp_ram)

; --- A, le dividende --------------------------------------------------------
        callf   eval            ; expression complete -> (bp+0)
        jrc     md_ret          ; echec : rien n'a ete pris
        test    (BP+0),080H     ; bit 7 : c'est une chaine
        jrnz    md_type

; ⛔ BP D'APRES LA PREMIERE EVALUATION, SAUVE EN ABSOLU. Le cadre pousse par
;    chknum vaut 15 octets, MESURE sur machine (BP 150 -> 135). Celui d'eval
;    ne l'est PAS : je ne le suppose donc pas, et je restaure BP par sa valeur
;    plutot que par un pmdf compte a la main. sv_bp0 et sv_bp1 etant tous deux
;    lisibles depuis le BASIC, l'ecart se mesurera au prochain essai.
        mv      [!sv_bp1],(bp_ram)

        callf   dec2bin         ; A -> entier 20 bits en (bp+1)..(bp+3)
        jrc     md_ret
        test    (BP+0),008H     ; bit 3 : le signe
        jrnz    md_neg

; ⛔ A EST MIS A L'ABRI ICI, ET C'EST TOUT L'INTERET DE CETTE VERSION. Le second
;    chknum ecrit sa valeur en (bp+0), et rien ne garantit qu'il ait d'abord
;    decale le cadre : la version precedente l'a suppose et perdait A.
        mvp     [!sv_a],(BP+1)

        mv      a,[x++]
        cmp     a,02CH          ; ',' obligatoire : il faut DEUX arguments
        jrnz    md_syn

; --- B, le diviseur ---------------------------------------------------------
        callf   eval            ; expression complete -> (bp+0)
        jrc     md_bad
        test    (BP+0),080H     ; bit 7 : c'est une chaine
        jrnz    md_type
        callf   dec2bin         ; B -> entier 20 bits en (bp+1)..(bp+3)
        jrc     md_bad
        test    (BP+0),008H
        jrnz    md_neg

        mv      a,[x++]
        cmp     a,029H          ; ')' obligatoire
        jrnz    md_syn

; --- B = 0 : erreur 21, celle que la ROM emploie pour le meme cas (0ECD67h) --
        mv      a,(BP+1)
        or      a,(BP+2)
        or      a,(BP+3)
        jrz     md_zero

        pushu   x               ; le point de reprise de l'interpreteur

; ============================================================================
; LA DIVISION BINAIRE A RESTAURATION -- 24 tours, tout en RAM interne
; ============================================================================
; Tout tient dans la QUEUE du cadre courant, (bp+4) a (bp+14), dont dec2bin n'a
; plus l'usage. C'est de la RAM interne, donc rapide, et cela reste valable quel
; que soit le cadre ou nous sommes.
;
;   A    : (bp+4),(bp+5),(bp+6)     relu de sv_a ; consomme par le decalage --
;                                   le quotient est jete, MOD n'en veut pas
;   cnt  : (bp+7)                   le compteur de tours
;   rst  : (bp+8),(bp+9),(bp+10)    le reste en construction
;   tmp  : (bp+12),(bp+13),(bp+14)  rst - B, garde s'il n'y a pas d'emprunt
;   B    : (bp+1),(bp+2),(bp+3)     la ou dec2bin vient de le mettre
;
; ⛔ SHL, ET SURTOUT PAS ROL -- C'EST LA QUE MOD RENDAIT 0 POUR TOUT.
;    Sur ce processeur, ROL/ROR sont CIRCULAIRES dans l'octet : la retenue recoit
;    bien le bit sortant, mais ce bit revient aussi en bas du MEME octet, et rien
;    ne passe a l'octet suivant. Une premiere version decalait A avec six « rol » :
;    chaque octet tournait sur lui-meme, le reste ne recevait jamais aucun bit et
;    valait donc 0 -- pour toutes les valeurs, ce qu'a montre la machine.
;
;    LA ROM TRANCHE, ET DANS LES DEUX SENS :
;      . elle CHAINE « shr » sur des octets consecutifs -- « F5 12 F5 13 F5 14
;        F5 15 F5 16 » en 0EEBB8h, un decalage de cinq octets. Seul un decalage
;        A TRAVERS la retenue peut se chainer ainsi ;
;      . et elle emploie « ror » la ou il faut LIRE les bits sans detruire
;        l'octet : bin2dec fait « ror (00Bh) / jrnc » huit fois par octet
;        (0EFBA3h), et huit rotations circulaires le rendent intact.
;    Les deux usages sont coherents, et ils s'excluent.
;
; 📄 Notre propre reference (SC62015_InstructionSet_Reference.md) decrit ROL et
;    SHL de la MEME facon, « via C » -- ce qui ne peut pas etre vrai des deux.
;    A corriger la-bas : la ROM est l'arbitre.
;
; ⛔ ET CES DECALAGES NE CONSULTENT PAS I. bin2dec enchaine « ror (00Bh) / jrnc »
;    alors que IL vaut encore 4 d'un dadl precedent, et n'en rotationne qu'un
;    octet. Les instructions BLOC, elles, bouclent I fois -- « mv il,00Fh /
;    mvl (000h),(00Fh) » de la ROM recopie bien 15 octets.
md_calc:
        mvp     (BP+4),[!sv_a]  ; A, revenu de l'abri
        mvp     (BP+8),000000H  ; reste = 0
        mv      (BP+7),00024    ; 24 tours : la largeur de A
md_loop:
        rc
        shl     (BP+4)          ; A <<= 1 ; le bit sortant part dans la retenue
        shl     (BP+5)
        shl     (BP+6)
        shl     (BP+8)          ; reste = reste<<1 | ce bit
        shl     (BP+9)
        shl     (BP+10)

        mvp     (BP+12),(BP+8)  ; tmp = reste
        rc                      ; SBCL retranche AUSSI la retenue : la vider
        mv      il,003
        sbcl    (BP+12),(BP+1)  ; tmp = reste - B, sur trois octets
        jrc     md_next         ; emprunt : reste < B, on ne retranche pas
        mvp     (BP+8),(BP+12)  ; sinon le reste devient tmp
md_next:
        dec     (BP+7)
        jrnz    md_loop

; --- rendre le reste exactement comme LPEEK rend le sien --------------------
; ⛔ LE DECALAGE DE chknum EST DESORMAIS MESURE, ET NON SUPPOSE. Le module a
;    laisse BP en RAM avant et apres son premier chknum ; releve sur la machine :
;    96h puis 87h, soit QUINZE octets tout rond. Le cadre du resultat est donc
;    celui d'un pmdf +15, et sv_a n'a plus a servir de pont -- ce qui le laisse
;    porter A, donc mesurable a son tour.
; sv_a a rendu A a la boucle : il sert maintenant de pont vers l'autre cadre.
        mvp     [!sv_a],(BP+8)          ; le reste, le temps de changer de cadre
        mv      (bp_ram),[!sv_bp1]      ; le cadre du resultat, en ABSOLU
        mv      (BP+0),000H             ; positif, simple precision
        mvp     (BP+1),[!sv_a]
        callf   bin2dec                 ; -> nombre BASIC en (bp+0)
        popu    x
        rc
md_ret:
        retf

; ============================================================================
; LES ERREURS
; ============================================================================
; ⛔ ON NE COMPTE PAS LES CADRES, ON RESTAURE BP. C'est la ce qui rend ces
;    sorties sures : rendre l'etat d'avant l'appel est la politique de la ROM
;    elle-meme (0ECD63h rend ce qu'il a pris avant de signaler l'erreur 21), et
;    une restauration ABSOLUE ne peut pas se tromper de compte -- meme apres un
;    dec2bin en echec, qui a deja rendu le sien (LOC_ECB5C : sc / pmdf +15 / ret).

; '(' manquante : la ROM remet le caractere en place avant de se plaindre
; (LOC_FD619) ; on fait de meme. Rien n'a encore ete pris, ni meme sv_bp0 ecrit.
md_syn0:
        dec     x
        mv      a,err_syn
        sc
        retf

; le second chknum ou son dec2bin a echoue : il porte deja son code d'erreur
md_bad:
        mv      (bp_ram),[!sv_bp0]
        sc
        retf

md_syn:
        mv      (bp_ram),[!sv_bp0]
        mv      a,err_syn
        sc
        retf

md_type:
        mv      (bp_ram),[!sv_bp0]
        mv      a,err_type      ; une chaine la ou un nombre est attendu
        sc
        retf

md_neg:
        mv      (bp_ram),[!sv_bp0]
        mv      a,err_range     ; operande negatif : hors du domaine annonce
        sc
        retf

md_zero:
        mv      (bp_ram),[!sv_bp0]
        mv      a,err_div
        sc
        retf

; ============================================================================
; PRIMITIVES PARTAGEES
; ============================================================================
; rd1str -- lit '(' expr_chaine ')'. CY=0 : chaine sur U, longueur (BP+4).
;           CY=1 : A = code d'erreur.  APPEL PROCHE.
rd1str:
rd_sp:
        mv      a,[x++]
        cmp     a,020H
        jrz     rd_sp
        cmp     a,028H
        jrz     rd_ev
        dec     x
        mv      a,err_syn
        sc
        ret
rd_ev:
        mv      [!sv_bp0],(bp_ram)
        callf   eval
        jrc     rd_er
        test    (BP+0),080H
        jrz     rd_ty
        mv      a,[x++]
        cmp     a,029H
        jrz     rd_ok
        mv      (bp_ram),[!sv_bp0]
        mv      a,err_syn
        sc
        ret
rd_ty:
        mv      (bp_ram),[!sv_bp0]
        mv      a,err_type
        sc
        ret
rd_ok:
        rc
        ret
rd_er:
        ret

; ret_str -- finaliseur, CONVENTION DE LEFT$ (LOC_FD7D3, 2026-09-14) : ecrire
;   (BP+1)=U et (BP+4)=longueur, garder (BP+0)=080h d'eval, NE PAS TOUCHER BP,
;   NI DE pmdf. Le pmdf casse la concatenation (il deseequilibre l'evaluateur
;   d'expression). BP doit etre au cadre d'UN SEUL eval a l'entree ici (REPT$,
;   qui en fait deux, restaure sv_bp1 avant de venir).
; U = base du resultat, IL = longueur.
ret_str:
        mv      (BP+0),080H
        mv      (BP+1),u
        mv      (BP+4),il
        rc
        retf

st_err:
        retf

; ============================================================================
; UCASE$ / LCASE$  --  transformation SUR PLACE
; ============================================================================
ucase_m3: db    0,0,0
ucase:
        call    rd1str
        jrc     st_err
        mv      y,u
        mv      il,(BP+4)
        mv      a,il
        cmp     a,000H
        jrz     uc_end
uc_lp:
        mv      a,[y]
        cmp     a,061H
        jrc     uc_pt
        cmp     a,07BH
        jrnc    uc_pt
        sub     a,020H
uc_pt:
        mv      [y],a
        inc     y
        dec     il
        jrnz    uc_lp
uc_end:
        mv      il,(BP+4)
        jp      ret_str

lcase_m3: db    0,0,0
lcase:
        call    rd1str
        jrc     st_err
        mv      y,u
        mv      il,(BP+4)
        mv      a,il
        cmp     a,000H
        jrz     lc_end
lc_lp:
        mv      a,[y]
        cmp     a,041H
        jrc     lc_pt
        cmp     a,05BH
        jrnc    lc_pt
        add     a,020H
lc_pt:
        mv      [y],a
        inc     y
        dec     il
        jrnz    lc_lp
lc_end:
        mv      il,(BP+4)
        jp      ret_str

; ============================================================================
; TRIM$ / LTRIM$ / RTRIM$
; ============================================================================
; tmode : 0 = les deux, 1 = a gauche, 2 = a droite.
; (BP+5) = decalage de debut ; (BP+6) = longueur elaguee ; (BP+4) = longueur d'origine.
trim_m3:  db    0,0,0
trim:
        mv      a,000H
        jr      tr_set
ltrim_m3: db    0,0,0
ltrim:
        mv      a,001H
        jr      tr_set
rtrim_m3: db    0,0,0
rtrim:
        mv      a,002H
tr_set:
        mv      [!tmode],a
        call    rd1str
        jrc     st_err

        mv      il,(BP+4)

; --- espaces de fin (sauf LTRIM) ---
        mv      a,[!tmode]
        cmp     a,001H
        jrz     tr_notrail
        mv      y,u
        mv      a,il
        add     y,a
tr_trl:
        mv      a,il
        cmp     a,000H
        jrz     tr_notrail
        mv      a,[y-1]
        cmp     a,020H
        jrnz    tr_notrail
        dec     y
        dec     il
        jr      tr_trl
tr_notrail:

; --- espaces de debut (sauf RTRIM) ---
        mv      (BP+5),000H
        mv      a,[!tmode]
        cmp     a,002H
        jrz     tr_nolead
        mv      y,u
tr_ld:
        mv      a,il
        cmp     a,000H
        jrz     tr_nolead
        mv      a,[y]
        cmp     a,020H
        jrnz    tr_nolead
        inc     y
        dec     il
        mv      a,(BP+5)
        inc     a
        mv      (BP+5),a
        jr      tr_ld
tr_nolead:
        mv      (BP+6),il

; --- copier la sous-plage AU SOMMET de la zone argument (haut vers bas) ---
        pushs   x
        mv      x,u
        mv      a,(BP+5)
        add     x,a
        mv      a,(BP+6)
        add     x,a                     ; X = fin de la source
        mv      y,u
        mv      a,(BP+4)
        add     y,a                     ; Y = fin de la destination
        mv      il,(BP+6)
        mv      a,il
        cmp     a,000H
        jrz     tr_moved
tr_cp:
        mv      a,[--x]
        mv      [--y],a
        dec     il
        jrnz    tr_cp
tr_moved:
        pops    x
        mv      a,(BP+4)
        sub     a,(BP+6)
        mv      y,u
        add     y,a
        mv      u,y                     ; U = base du resultat
        mv      il,(BP+6)
        jp      ret_str

; ============================================================================
; REPT$ (nombre, caractere)
; ============================================================================
; (BP+6) = compte ; (BP+4) = longueur de la chaine caractere ; sv_bp1 = cadre du
; 1er eval (celui du resultat).
rept_m3:  db    0,0,0
rept:
rp_sp:
        mv      a,[x++]
        cmp     a,020H
        jrz     rp_sp
        cmp     a,028H
        jrnz    rp_syn0
        mv      [!sv_bp0],(bp_ram)

; --- arg 1 : le NOMBRE (0..255) ---
        callf   eval
        jrc     rp_ret
        test    (BP+0),080H
        jrnz    rp_type
        mv      [!sv_bp1],(bp_ram)      ; cadre du resultat
        callf   dec2bin
        jrc     rp_ret
        test    (BP+0),008H
        jrnz    rp_range
        mv      a,(BP+2)
        or      a,(BP+3)
        jrnz    rp_range
        mv      a,(BP+1)
        mv      [!rp_n],a

        mv      a,[x++]
        cmp     a,02CH
        jrnz    rp_syn

; --- arg 2 : le CARACTERE (chaine, 1er octet) ---
        callf   eval
        jrc     rp_bad
        test    (BP+0),080H
        jrz     rp_type
        mv      a,(BP+4)
        cmp     a,000H
        jrz     rp_ec
        mv      y,u
        mv      a,[y]
        jr      rp_hc
rp_ec:
        mv      a,020H
rp_hc:
        mv      [!rp_c],a

        mv      a,[x++]
        cmp     a,029H
        jrnz    rp_syn

; --- ajuster U (cadre du 2e eval), remplir ---
        mv      a,[!rp_n]
        mv      (BP+6),a                ; compte
        cmp     (BP+4),a                ; len(c$) - n : carry si n>len ; Z si egaux
        jrz     rp_fill
        jrnc    rp_up
; n > len : abaisser U de (n - len)
        mv      ba,00000H
        mv      a,(BP+6)
        sub     a,(BP+4)                ; BA = n - len
        pushs   x
        callf   alloc
        jrc     rp_buf
        pops    x
        jr      rp_fill
rp_up:
        mv      a,(BP+4)
        sub     a,(BP+6)
        mv      y,u
        add     y,a
        mv      u,y
rp_fill:
        mv      y,u
        mv      il,(BP+6)
        mv      a,il
        cmp     a,000H
        jrz     rp_done
        mv      a,[!rp_c]
rp_fl:
        mv      [y++],a
        dec     il
        jrnz    rp_fl
rp_done:
        mv      il,(BP+6)               ; longueur, gardee dans IL
        mv      (bp_ram),[!sv_bp1]      ; revenir au cadre du 1er eval
        jp      ret_str

; --- erreurs de REPT$ ---
rp_syn0:
        dec     x
        mv      a,err_syn
        sc
        retf
rp_ret:
        retf
rp_bad:
        mv      (bp_ram),[!sv_bp0]
        sc
        retf
rp_type:
        mv      (bp_ram),[!sv_bp0]
        mv      a,err_type
        sc
        retf
rp_syn:
        mv      (bp_ram),[!sv_bp0]
        mv      a,err_syn
        sc
        retf
rp_range:
        mv      (bp_ram),[!sv_bp0]
        mv      a,err_range
        sc
        retf
rp_buf:
        pops    x
        mv      (bp_ram),[!sv_bp0]
        mv      a,err_buf
        sc
        retf

; ============================================================================
; SREPT$ (nombre, chaine)  --  <nombre> repetitions de la CHAINE ENTIERE
; ============================================================================
; SREPT$(3,"ABC") -> "ABCABCABC". resultat = nombre * longueur, <= 255.
; Comme REPT$ mais copie toute la chaine. La chaine s$ est sur U [U, U+L) ; on
; abaisse U de (resultlen - L) et on recopie s$ (n-1) fois SOUS la copie du haut
; (qui est deja s$), pour finir au ras de la pile.
srept_m3: db    0,0,0
srept:
sr_sp:
        mv      a,[x++]
        cmp     a,020H
        jrz     sr_sp
        cmp     a,028H
        jrnz    sr_syn0
        mv      [!sv_bp0],(bp_ram)
        callf   eval                    ; arg1 : nombre
        jrc     sr_ret
        mv      [!sv_bp1],(bp_ram)
        test    (BP+0),080H
        jrnz    sr_type
        callf   dec2bin
        jrc     sr_ret
        test    (BP+0),008H
        jrnz    sr_range
        mv      a,(BP+2)
        or      a,(BP+3)
        jrnz    sr_range
        mv      a,(BP+1)
        mv      [!sr_n],a
        mv      a,[x++]
        cmp     a,02CH
        jrnz    sr_syn
        callf   eval                    ; arg2 : chaine
        jrc     sr_bad
        test    (BP+0),080H
        jrz     sr_type
        mv      a,(BP+4)
        mv      (BP+6),a                ; L = longueur de la chaine
        mv      a,[x++]
        cmp     a,029H
        jrnz    sr_syn
; --- resultlen = n * L, controle <= 255 (dans (BP+5)) ---
        mv      a,[!sr_n]
        mv      (BP+5),a
        mv      il,(BP+5)               ; il = n
        mv      (BP+5),000H             ; (BP+5) = accumulateur
        mv      a,il
        cmp     a,000H
        jrz     sr_lenok                ; n = 0 -> resultlen 0
sr_mul:
        mv      a,(BP+5)
        add     a,(BP+6)                ; += L  (0x42 ADD A,(n))
        jrc     sr_range                ; > 255
        mv      (BP+5),a
        dec     il
        jrnz    sr_mul
sr_lenok:
; --- ajuster U ; (BP+5)=resultlen, (BP+6)=L ---
        mv      a,(BP+5)
        cmp     (BP+6),a                ; L - resultlen : carry si resultlen>L
        jrc     sr_grow
        jrz     sr_done                 ; resultlen = L (n=1) : U inchange
; resultlen < L (n=0) : remonter U de (L - resultlen)
        mv      a,(BP+6)
        sub     a,(BP+5)
        mv      y,u
        add     y,a
        mv      u,y
        jr      sr_done
sr_grow:
        mv      [!sr_src],u             ; Us = base de s$ (copie du haut), avant alloc
        mv      ba,00000H
        mv      a,(BP+5)
        sub     a,(BP+6)                ; BA = resultlen - L = (n-1)*L
        pushs   x
        callf   alloc
        jrc     sr_buf
        mv      y,u                     ; dst = nouvelle base
        mv      a,[!sr_n]
        dec     a
        mv      [!sr_cnt],a             ; n-1 copies a poser sous le haut
sr_oc:
        mv      a,[!sr_cnt]
        cmp     a,000H
        jrz     sr_grown
        mv      x,[!sr_src]             ; src = s$ du haut (intact)
        mv      il,(BP+6)               ; L
sr_ic:
        mv      a,[x++]
        mv      [y++],a
        dec     il
        jrnz    sr_ic
        mv      a,[!sr_cnt]
        dec     a
        mv      [!sr_cnt],a
        jr      sr_oc
sr_grown:
        pops    x
sr_done:
        mv      il,(BP+5)               ; longueur du resultat
        mv      (bp_ram),[!sv_bp1]
        jp      ret_str
sr_syn0:
        dec     x
        mv      a,err_syn
        sc
        retf
sr_ret:
        retf
sr_bad:
        mv      (bp_ram),[!sv_bp0]
        sc
        retf
sr_type:
        mv      (bp_ram),[!sv_bp0]
        mv      a,err_type
        sc
        retf
sr_syn:
        mv      (bp_ram),[!sv_bp0]
        mv      a,err_syn
        sc
        retf
sr_range:
        mv      (bp_ram),[!sv_bp0]
        mv      a,err_range
        sc
        retf
sr_buf:
        pops    x
        mv      (bp_ram),[!sv_bp0]
        mv      a,err_buf
        sc
        retf

; ============================================================================
; INSTR ([debut,] texte, recherche)  --  position 1-based, 0 si absent
; ============================================================================
; Rend un NOMBRE (comme LEN/ASC) : lit les chaines, LIBERE les temporaires de U
; (add u,longueur, d'apres BAS_LEN 0EECA8h), convertit par bin2dec, BP restaure
; au cadre du 1er eval (comme MOD). recherche a U [..LS) ; texte a U+LS [..LT).
instr_m3: db    0,0,0
instr:
in_sp:
        mv      a,[x++]
        cmp     a,020H
        jrz     in_sp
        cmp     a,028H
        jrnz    in_syn0
        mv      [!sv_bp0],(bp_ram)
; --- arg 1 : nombre (debut) OU chaine (texte) ---
        callf   eval
        jrc     in_ret
        mv      [!sv_bp1],(bp_ram)
        test    (BP+0),080H
        jrnz    in_a1str
        callf   dec2bin             ; debut numerique
        jrc     in_ret
        test    (BP+0),008H
        jrnz    in_range
        mv      a,(BP+2)
        or      a,(BP+3)
        jrnz    in_range
        mv      a,(BP+1)
        cmp     a,000H
        jrz     in_range            ; debut 0 interdit (1-based)
        mv      [!in_start],a
        mv      a,[x++]
        cmp     a,02CH
        jrnz    in_syn
        callf   eval                ; texte
        jrc     in_bad
        test    (BP+0),080H
        jrz     in_type
        jr      in_havetext
in_a1str:
        mv      a,001H
        mv      [!in_start],a
in_havetext:
        mv      a,(BP+4)
        mv      [!in_lt],a          ; longueur du texte
        mv      a,[x++]
        cmp     a,02CH
        jrnz    in_syn
        callf   eval                ; recherche
        jrc     in_bad
        test    (BP+0),080H
        jrz     in_type
        mv      a,[x++]
        cmp     a,029H
        jrnz    in_syn
; --- recherche : mise en place ---
; (BP+5) = maxp ; (BP+6) = octet temporaire de comparaison ; p en variable module
; (on n'utilise QUE (BP+5)/(BP+6), prouves surs ; le cadre d'eval peut ne pas
;  atteindre (BP+7)).
        mv      a,[!in_lt]
        sub     a,(BP+4)            ; LT - LS
        jrc     in_notfound         ; LS > LT
        mv      (BP+5),a            ; maxp (0-based)
        mv      a,[!in_start]
        dec     a
        mv      [!in_p],a           ; p = debut - 1
in_outer:
        mv      a,[!in_p]
        cmp     (BP+5),a            ; maxp - p : carry si p>maxp
        jrc     in_notfound
in_cmp:
        pushs   x
        mv      x,u
        mv      a,(BP+4)
        add     x,a
        mv      a,[!in_p]
        add     x,a                 ; X = texte + p
        mv      y,u                 ; Y = recherche
        mv      il,(BP+4)
        mv      a,il
        cmp     a,000H
        jrz     in_hit              ; recherche vide
in_ck:
        mv      a,[x++]
        mv      (BP+6),a            ; caractere du texte
        mv      a,[y++]
        cmp     (BP+6),a            ; (textchar) - (searchchar) : Z si egaux
        jrnz    in_miss
        dec     il
        jrnz    in_ck
in_hit:
        pops    x
        mv      a,[!in_p]
        inc     a
        jr      in_found
in_miss:
        pops    x
        mv      a,[!in_p]
        inc     a
        mv      [!in_p],a
        jr      in_outer
in_notfound:
        mv      a,000H
in_found:
        mv      [!in_res],a
; --- liberer les deux chaines de U, puis rendre le nombre ---
        mv      a,(BP+4)
        add     u,a
        mv      a,[!in_lt]
        add     u,a
        mv      (bp_ram),[!sv_bp1]
        mv      (BP+0),000H
        mv      a,[!in_res]
        mv      (BP+1),a
        mvw     (BP+2),00000H
        pushu   x               ; ⛔ bin2dec ECRASE X (le point de reprise) : le sauver
        callf   bin2dec
        popu    x
        rc
        retf
in_syn0:
        dec     x
        mv      a,err_syn
        sc
        retf
in_ret:
        retf
in_bad:
        mv      (bp_ram),[!sv_bp0]
        sc
        retf
in_type:
        mv      (bp_ram),[!sv_bp0]
        mv      a,err_type
        sc
        retf
in_syn:
        mv      (bp_ram),[!sv_bp0]
        mv      a,err_syn
        sc
        retf
in_range:
        mv      (bp_ram),[!sv_bp0]
        mv      a,err_range
        sc
        retf

; ============================================================================
; XCONSOLE [debut][,[nombre]]  --  la fenetre de la console (INSTRUCTION)
; ============================================================================
; Borne la console aux lignes debut .. debut+nombre-1 de l'ecran de 4 lignes.
;
;   XCONSOLE            0,4 : l'ecran entier, l'etat normal
;   XCONSOLE ,2         lignes 0-1 ; les lignes 2-3 restent figees
;   XCONSOLE 2          lignes 2-3 (le nombre omis va jusqu'en bas)
;   XCONSOLE 1,2        lignes 1-2
;
; Refus : debut > 3, nombre nul, ou debut+nombre > 4 -> erreur 33 ; une chaine
; -> erreur 90 ; un separateur autre que ',' -> erreur 10.
;
; LE LEVIER EST lcd_height (0BFC9Eh), ET NON LE CURSEUR 0BFC27h/0BFC28h.
;    Le pilote d'ecran defile quand (bh) atteint lcd_height (0F2B6Ah), clear_disp
;    n'efface que les lignes 0 .. lcd_height-1 (0F2771h), et LOCATE refuse un Y
;    au-dela (0FC682h). ✅ Mesure sur machine par J.-F. Albouy : POKE &BFC9E,2
;    confine affichage, defilement et CLS aux lignes 0-1, et CLS ne remet PAS la
;    hauteur a 4.
;
; POUR debut > 0, LA ROM NE SUFFIT PLUS : son defilement part TOUJOURS de la
;    ligne 0 (0F27F1h, recopie par 0F28E3h) et emporterait les lignes figees.
;    XCONSOLE branche alors le FILTRE D'ECRITURE (xf_entry, plus bas) sur le
;    handle 0, et l'en debranche quand debut revient a 0.
;
; ⛔ LA FENETRE SURVIT A LA FIN DU PROGRAMME. Mesure : l'invite du mode direct
;    reste dans les lignes de la fenetre, et seul MENU puis BASIC rend l'ecran.
;    Un programme doit donc finir par XCONSOLE (puis CLS) -- apres une erreur ou
;    un BREAK, MENU puis BASIC.
;
; La fin d'instruction est celle de 0F617Ch, que lisent CONSOLE et LOCATE :
; ':' ou 0Dh, regardes sans etre consommes. Les espaces se sautent comme en
; 0FB2D9h. BP est rendu en ABSOLU (sv_bp0) sur tous les chemins : une
; instruction rend BP inchange (MODE-EMPLOI §6.1).
xconsole:
        mv      [!sv_bp0],(bp_ram)      ; BP d'entree
        mv      a,000H
        mv      [!xc_t],a               ; debut par defaut : 0
        mv      a,0FFH
        mv      [!xc_c],a               ; nombre : absent
        call    xc_skip                 ; A = premier non-espace, X dessus
        cmp     a,03AH                  ; ':'
        jrz     xc_apply
        cmp     a,00DH                  ; fin de ligne
        jrz     xc_apply                ; XCONSOLE seul
        cmp     a,02CH
        jrz     xc_comma                ; XCONSOLE ,n : debut omis
        call    xc_num                  ; le debut
        jrc     xc_err
        mv      [!xc_t],a
        call    xc_skip
        cmp     a,03AH
        jrz     xc_apply
        cmp     a,00DH
        jrz     xc_apply
        cmp     a,02CH
        jrnz    xc_syn
xc_comma:
        inc     x                       ; consommer la virgule
        call    xc_skip
        cmp     a,03AH
        jrz     xc_apply
        cmp     a,00DH
        jrz     xc_apply                ; XCONSOLE d, : nombre omis
        call    xc_num                  ; le nombre de lignes
        jrc     xc_err
        mv      [!xc_c],a

xc_apply:
        mv      a,[!xc_t]
        cmp     a,004H
        jrnc    xc_range                ; debut au-dela de la ligne 3
        mv      il,a                    ; IL = debut
        mv      a,[!xc_c]
        cmp     a,0FFH
        jrz     xc_full                 ; nombre omis : jusqu'en bas
        cmp     a,000H
        jrz     xc_range                ; une fenetre de zero ligne
        add     a,il                    ; A = debut + nombre = la hauteur
        jrc     xc_range
        cmp     a,005H
        jrnc    xc_range                ; deborde sous la ligne 3
        jr      xc_store
xc_full:
        mv      a,004H
xc_store:
        mv      [lcd_height],a
        mv      [!xc_top],il            ; le debut, que XCLS et le filtre reliront
        pushu   x                       ; xf_on et xf_off se servent de X et de I
        pushu   i
        mv      a,il
        cmp     a,000H
        jrz     xc_unhook
        call    xf_on                   ; fenetre haute : le filtre est necessaire
        jr      xc_hooked
xc_unhook:
        call    xf_off                  ; debut 0 : la ROM suffit
xc_hooked:
        popu    i
        popu    x
        mv      (bp_ram),[!sv_bp0]
        rc
        retf

xc_syn:
        mv      a,err_syn
        jr      xc_err
xc_range:
        mv      a,err_range
xc_err:
        mv      (bp_ram),[!sv_bp0]
        sc
        retf

; xc_skip -- saute les espaces ; X reste SUR le premier non-espace, rendu dans A.
;            APPEL PROCHE.
xc_skip:
        mv      a,[x]
        cmp     a,020H
        jrnz    xs_ret
        inc     x
        jr      xc_skip
xs_ret:
        ret

; xc_num -- une expression numerique entiere de 0 a 255.
;           CY=0 : A = la valeur, BP rendu a sv_bp0.
;           CY=1 : A = code d'erreur, BP rendu a sv_bp0.  APPEL PROCHE.
xc_num:
        callf   eval
        jrc     xn_fail                 ; A porte deja le code
        test    (BP+0),080H
        jrnz    xn_type
        callf   dec2bin
        jrc     xn_fail
        test    (BP+0),008H
        jrnz    xn_range                ; negatif
        mv      a,(BP+2)
        or      a,(BP+3)
        jrnz    xn_range                ; au-dela de 255
        mv      a,(BP+1)
        mv      (bp_ram),[!sv_bp0]      ; rendre le cadre d'eval
        rc
        ret
xn_type:
        mv      a,err_type
        jr      xn_fail
xn_range:
        mv      a,err_range
xn_fail:
        mv      (bp_ram),[!sv_bp0]
        sc
        ret

; ============================================================================
; XCLS  --  efface la fenetre de XCONSOLE (INSTRUCTION)
; ============================================================================
; Pendant de CLS, qui reste celui de la ROM et efface les lignes 0 ..
; lcd_height-1, lignes figees comprises. XCLS n'efface que xc_top ..
; lcd_height-1 et place le curseur en (0,xc_top).
;
; Calque sur 0F9307h, la fin de CLS, avec les commandes documentees du device 0 :
;   CLS  : 51h clear_disp            / 45h cursor_type, BA=0 / curseur (0,0)
;   XCLS : 49h clear_line par ligne  / 45h cursor_type, BA=0 / curseur (0,xc_top)
; et, comme CLS (0F9367h), les bits 0-1 de [(basptr)+070h] remis a zero --
; ceux que LOCATE arme (0FC698h).
;
; La hauteur est RELUE dans lcd_height a chaque appel, et non memorisee : si
; l'editeur l'a changee, XCLS suit la ROM au lieu de la contredire.
xcls:
        pushu   x                       ; le point de reprise
        pushu   i
        mv      a,[!xc_top]
        mv      [!xcl_y],a
xl_loop:
        mv      a,[!xcl_y]
        mv      (bh),a                  ; ordonnee de la ligne (argument de 49h)
        mv      a,[lcd_height]
        cmp     (bh),a                  ; ligne - hauteur : NC = hors fenetre
        jrnc    xl_done
        mvw     (cl),00000H             ; device 0, lecteur 0
        mv      il,d0_clear_line
        callf   iocs_call
        mv      a,[!xcl_y]
        inc     a
        mv      [!xcl_y],a
        jr      xl_loop
xl_done:
        mv      il,d0_cursor_type
        sub     ba,ba                   ; pas de curseur, comme 0F930Eh
        mvw     (cl),00000H
        callf   iocs_call
        mv      a,000H
        mv      [scrn_crsr_x],a
        mv      a,[!xc_top]
        mv      [scrn_crsr_y],a
        mv      x,(basptr)
        mv      a,[x+070H]
        and     a,0FCH                  ; les bits de LOCATE, comme CLS
        mv      [x+070H],a
        popu    i
        popu    x
        rc
        retf

; ============================================================================
; LE FILTRE D'ECRITURE DE STDO:  --  confine le defilement a la fenetre
; ============================================================================
; ⛔ LE FILTRE NE SE CHAINE PAS DANS d_link, ET C'EST LA MACHINE QUI LE DIT.
;    L'ecriture par le FCS ne passe PAS par iocs_call : en 0E0907h, il saute
;    (retf) a l'adresse rangee en [bloc+2] du bloc de controle du handle, et
;    cette adresse est memorisee a l'OUVERTURE (0E07F1h). Releve dans la System
;    Data Area d'un PC-E500S reel (Samples/Extraction/s1-1.bin) :
;
;      bloc du handle 0 en 0BEE48h : 00 00 E7 21 0F A2 02
;                                    |  |  \______/ \
;                                device lecteur  0F21E7h = drv_display, attribut
;
;    Un en-tete ajoute en tete de d_link (la methode de MEMCHECK) ne verrait donc
;    jamais un PRINT. On remplace l'adresse du bloc du handle 0 par xf_entry, et
;    le filtre transmet a l'ancienne adresse -- recopiee dans les operandes de
;    xf_pass et xf_call (auto-modification, comme MEMCHECK). Si la ROM rouvre
;    STDO:, le filtre disparait simplement : l'echec est sans danger.
;
; LE BLOC DE CONTROLE se trouve comme en 0E0698h / 0E066Ah :
;    numero = [fhandle + handle] ; bloc = [(iocsw)] + [(iocsw)+25h]
;    + numero * 1Fh, borne par [(iocsw)+27h] ; octet 0 = device (0FFh = libre).
;
; LE PRINCIPE : DEFILER AVANT LA ROM. Pour un octet, le pilote fait (0F2A47h) :
;    affichable        : retour a la ligne differe (0F2B57h : X >= largeur ->
;                        X=0, Y+1), puis 0F2B6Ah (Y >= lcd_height -> defilement
;                        de la ROM, Y = lcd_height-1), puis l'affichage ;
;    0Dh               : 0F2B6Ah seul ;
;    08 09 0A 0B 1C 1D 1F : 0F2B57h puis 0F2B6Ah ;
;    07 0C 1E et le reste : pas de 0F2B6Ah.
; Le filtre calcule la ligne que verra 0F2B6Ah. Si la ROM allait defiler, il
; defile LUI-MEME les lignes debut .. lcd_height-1 (55h pattern_read, 56h
; pattern_write, 49h clear_line), puis remonte Y pour que la ROM ne defile plus.
; L'octet est ensuite transmis tel quel : le pilote fait tout le reste.
;
; ⚠️ SEULS LES ECRITURES DU HANDLE 0 SONT VUES. Un OPEN "SCRN:" ouvre un autre
;    handle, qui garde l'adresse de la ROM.
; ⚠️ NE PAS RECHARGER LE MODULE FILTRE BRANCHE. Entre LOAD M et CALL &BF000, le
;    handle 0 designerait du code ecrase. Faire XCONSOLE avant de recharger ;
;    CALL &BF000 debranche ensuite tout filtre reste dans la zone du module.

; xf_entry -- l'entree du filtre : memes registres qu'une entree de pilote.
xf_entry:
        pushu   ba
        mv      ba,i
        cmp     a,00DH                  ; write_byte
        jrz     xf_wbyte
        cmp     a,00BH                  ; write_block
        jrz     xf_wblock
        popu    ba
xf_pass:
        jpf     0F21E7H                 ; OPERANDE REECRIT par xf_on
xf_wbyte:
        popu    ba                      ; A = l'octet, I = 0Dh
        pushu   x
        pushu   y
        pushu   i
        pushu   ba
        call    xf_pre
        popu    ba
        popu    i
        popu    y
        popu    x
        jr      xf_pass

; write_block : X = source, Y = compte. On le rend octet par octet au pilote,
; chacun precede de son controle ; Y est rendu tel quel, comme 0F2A18h.
xf_wblock:
        popu    ba
        pushu   y
xb_lp:
        inc     y
        dec     y
        jrz     xb_end
        mv      a,[x++]
        pushu   x
        pushu   y
        pushu   a
        call    xf_pre
        popu    a
        mv      il,00DH
        call    xf_call                 ; write_byte de l'ancien pilote
        popu    y
        popu    x
        dec     y
        jr      xb_lp
xb_end:
        popu    y
        rc
        retf

; xf_call -- appelle l'ancien pilote, commande dans IL.  APPEL PROCHE.
xf_call:
        callf   0F21E7H                 ; OPERANDE REECRIT par xf_on
        ret

; xf_pre -- A = l'octet a ecrire. Defile la fenetre si la ROM allait le faire.
;           Detruit A, I, X, Y, (bl), (bh).  APPEL PROCHE.
xf_pre:
        mv      (bl),a                  ; l'octet, le temps de le classer
        mv      a,[!xc_top]
        cmp     a,000H
        jrz     xp_none                 ; debut 0 : la ROM suffit
        mv      (bh),a
        mv      a,[lcd_height]
        cmp     (bh),a                  ; debut - hauteur : NC = pas de fenetre
        jrnc    xp_none
        mv      a,(bl)
        cmp     a,020H
        jrnc    xp_wrap                 ; affichable
        test    [ctrl_disp],040H
        jrnz    xp_wrap                 ; code de controle affiche (0F2A56h)
        cmp     a,00DH
        jrz     xp_nw                   ; CR : 0F2B6Ah sans 0F2B57h
        cmp     a,008H
        jrc     xp_none                 ; 00-07
        cmp     a,00CH
        jrc     xp_wrap                 ; 08 09 0A 0B
        cmp     a,01CH
        jrc     xp_none                 ; 0C-1B
        cmp     a,01EH
        jrz     xp_none                 ; 1E, curseur vers le haut
xp_wrap:                                ; 1C 1D 1F et les affichables
        mv      il,000H
        mv      (bl),[scrn_crsr_x]
        mv      a,[lcd_width]
        cmp     (bl),a                  ; X - largeur : NC = retour differe
        jrc     xp_chk
        mv      il,001H
        jr      xp_chk
xp_nw:
        mv      il,000H
xp_chk:
        mv      a,[scrn_crsr_y]
        add     a,il                    ; la ligne que verra 0F2B6Ah
        mv      (bh),a
        mv      a,[lcd_height]
        cmp     (bh),a                  ; NC : la ROM defilerait
        jrc     xp_none
        mv      [!xf_w],il
        call    xf_scroll
        mv      a,[lcd_height]
        dec     a
        mv      il,[!xf_w]
        sub     a,il                    ; lcd_height-1-retour : plus de defilement ROM
        mv      [scrn_crsr_y],a
xp_none:
        ret

; xf_scroll -- remonte d'une ligne les lignes debut+1 .. lcd_height-1, puis
;              efface la derniere.  APPEL PROCHE.
xf_scroll:
        mv      a,[!xc_top]
        mv      [!xf_y],a
xs_lp:
        mv      a,[!xf_y]
        inc     a
        mv      (bh),a                  ; la ligne du dessous
        mv      a,[lcd_height]
        cmp     (bh),a
        jrnc    xs_clr                  ; plus rien a remonter
        mv      x,xf_buf
        mv      il,d0_pattern_read
        call    xf_call
        mv      a,[!xf_y]
        mv      (bh),a
        mv      x,xf_buf
        mv      il,d0_pattern_write
        call    xf_call
        mv      a,[!xf_y]
        inc     a
        mv      [!xf_y],a
        jr      xs_lp
xs_clr:
        mv      a,[lcd_height]
        dec     a
        mv      (bh),a
        mv      il,d0_clear_line
        call    xf_call
        ret

; xf_fcb -- X = le bloc de controle du handle 0 ; CY=1 s'il n'est pas l'ecran.
;           Detruit A, I, (bl).  APPEL PROCHE.
xf_fcb:
        mv      a,[fhandle]             ; handle 0 -> numero de bloc
        mv      (bl),a
        mv      x,(iocsw)
        mv      a,[x+027H]              ; nombre de blocs
        cmp     (bl),a
        jrnc    xfc_no
        mv      i,[x+025H]
        add     x,i                     ; le premier bloc
        mv      i,0001FH                ; 31 octets par bloc
xfc_lp:
        mv      a,(bl)
        cmp     a,000H
        jrz     xfc_at
        add     x,i
        dec     (bl)
        jr      xfc_lp
xfc_at:
        mv      a,[x]                   ; le device du bloc
        cmp     a,000H
        jrnz    xfc_no                  ; libre (0FFh) ou pas l'ecran
        rc
        ret
xfc_no:
        sc
        ret

; xf_on -- branche le filtre sur le handle 0.  APPEL PROCHE.
;          Deja branche (adresse dans la zone du module) : ne rien faire, sans
;          quoi le filtre se transmettrait a lui-meme.
xf_on:
        call    xf_fcb
        jrc     xon_ret
        mv      a,[x+004H]
        cmp     a,00BH
        jrnz    xon_set
        mv      a,[x+003H]
        cmp     a,0F0H
        jrnc    xon_ret                 ; 0BF000h-0BFFFFh : deja nous
xon_set:
        mv      y,[x+002H]              ; l'adresse en place : la ROM, ou un autre
        mv      [!xf_pass+1],y
        mv      [!xf_call+1],y
        mv      y,xf_entry
        mv      [x+002H],y              ; une seule instruction : atomique
xon_ret:
        ret

; xf_off -- debranche le filtre : rend l'adresse gardee dans xf_pass. Apres un
;           rechargement du module, c'est celle de l'assemblage, 0F21E7h.
;           APPEL PROCHE.
xf_off:
        call    xf_fcb
        jrc     xof_ret
        mv      a,[x+004H]
        cmp     a,00BH
        jrnz    xof_ret
        mv      a,[x+003H]
        cmp     a,0F0H
        jrc     xof_ret                 ; pas un filtre de la zone du module
        mv      y,[!xf_pass+1]
        mv      [x+002H],y
xof_ret:
        ret

; ============================================================================
; LES QUATRE ENTREES
; ============================================================================
kw_table:
        db      5,'LPEEK',tk_lp
        db      5,'WPEEK',tk_wp
        db      5,'LPOKE',tk_lpo
        db      3,'MOD',tk_mod
        db      6,'UCASE$',tk_uc
        db      6,'LCASE$',tk_lc
        db      5,'TRIM$',tk_tr
        db      6,'LTRIM$',tk_lt
        db      6,'RTRIM$',tk_rt
        db      5,'REPT$',tk_rp
        db      6,'SREPT$',tk_sr
        db      5,'INSTR',tk_in
        db      8,'XCONSOLE',tk_xc
        db      4,'XCLS',tk_xcl
        db      0                       ; fin de table

disp_table:
; Trois entrees de 4 octets, puis le terminateur. Le quartet haut du 3e octet
; d'adresse est un DRAPEAU : 040h = fonction, routine a l'adresse + 3 ; 080h =
; instruction, routine a l'adresse telle quelle. LPOKE est du second genre, et
; n'a donc pas de prefixe de trois octets.
        db      tk_lp
        db      lpeek_m3
        db      lpeek_m3/256
        db      lpeek_m3/65536+040H
        db      tk_wp
        db      wpeek_m3
        db      wpeek_m3/256
        db      wpeek_m3/65536+040H
        db      tk_lpo
        db      lpoke
        db      lpoke/256
        db      lpoke/65536+080H
        db      tk_mod
        db      modu_m3
        db      modu_m3/256
        db      modu_m3/65536+040H
        db      tk_uc, ucase_m3, ucase_m3/256, ucase_m3/65536+040H
        db      tk_lc, lcase_m3, lcase_m3/256, lcase_m3/65536+040H
        db      tk_tr, trim_m3,  trim_m3/256,  trim_m3/65536+040H
        db      tk_lt, ltrim_m3, ltrim_m3/256, ltrim_m3/65536+040H
        db      tk_rt, rtrim_m3, rtrim_m3/256, rtrim_m3/65536+040H
        db      tk_rp, rept_m3,  rept_m3/256,  rept_m3/65536+040H
        db      tk_sr, srept_m3, srept_m3/256, srept_m3/65536+040H
        db      tk_in, instr_m3, instr_m3/256, instr_m3/65536+040H
        db      tk_xc,  xconsole, xconsole/256, xconsole/65536+080H   ; instructions :
        db      tk_xcl, xcls,     xcls/256,     xcls/65536+080H       ; pas de +3
        db      0                       ; fin de table

; ============================================================================
; LES CROCHETS D'ORIGINE, pour desinstaller
; ============================================================================
; Le premier operande, hors d'atteinte du second chknum. Il n'est PLUS ecrase
; ensuite : apres un appel, LPEEK &BF1EC rend A tel que dec2bin l'a converti.
; C'est notre seul point de mesure, et le module doit rester assez court pour
; que le BASIC ne vienne pas le manger -- le vidage du 2026-09-05 montre du
; texte BASIC des 0BF1F7h.
sv_a:     db    0,0,0
sv_bp0:   db    0             ; BP a l'entree -- l'etat a rendre en erreur
sv_bp1:   db    0             ; BP apres la 1re evaluation -- cadre du resultat

; ⛔ LES TROIS TEMOINS DE MESURE ONT ETE RETIRES LE 2026-09-05, une fois MOD
;    valide sur machine. Ils portaient A et B tels que dec2bin les rendait, et le
;    reste au sortir de la boucle ; c'est par eux que la cause a ete trouvee deux
;    fois, la ou le raisonnement s'etait trompe. Les remettre est l'affaire de
;    trois « mvp [!dbg_x],(BP+n) » et de trois mots de 3 octets -- le faire
;    plutot que de deviner, si la fonction se remet a mentir.


tmode:    db    0
rp_n:     db    0
rp_c:     db    0
in_start: db    0
in_lt:    db    0
in_res:   db    0
in_p:     db    0
sr_n:     db    0
sr_cnt:   db    0
sr_src:   db    0,0,0
xc_t:     db    0             ; XCONSOLE : debut lu
xc_c:     db    0             ; XCONSOLE : nombre lu, 0FFh = absent
xc_top:   db    0             ; la premiere ligne de la fenetre, relue par XCLS
xcl_y:    db    0             ; XCLS : la ligne en cours d'effacement
xf_w:     db    0             ; filtre : 1 si retour a la ligne differe
xf_y:     db    0             ; filtre : la ligne en cours de remontee
xf_buf:   ds    240           ; filtre : le motif d'une ligne (240 colonnes)
old_kw:   db    0,0,0
old_disp: db    0,0,0

        end
