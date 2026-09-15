; ============================================================================
; STREXT.ASM -- FONCTIONS CHAINE ajoutees au BASIC (fusionnees dans BASEXT.ASM)
; ============================================================================
; Convention chaine ETABLIE SUR MACHINE le 2026-09-14 :
;
;   LIRE un argument chaine (d'apres SUB_FC613, lecteur de LEFT$) :
;     callf eval ; test (BP+0),080h  (bit 7 = chaine, sinon erreur 90)
;     -> chaine SUR U (adresse = U), longueur en (BP+4). eval a deja pose
;        (BP+0)=080h et (BP+1)=U, et ABAISSE BP de 15 (comme chknum).
;
;   RENDRE une chaine : (BP+0)=080h ; (BP+1)=U ; (BP+4)=IL, avec BP au cadre
;     d'UN SEUL eval (BP d'entree - 15), SANS pmdf -- la convention de LEFT$,
;     dont la fin LOC_FD7D3 n'a aucun pmdf. Le resultat DOIT etre a l'adresse U,
;     IL = sa longueur.
;     ⛔ CET EN-TETE DISAIT « repliquer LOC_FD6F9 : pmdf (bp_ram),0F1h
;        INDISPENSABLE ». FAUX EN GENERAL (corrige le 2026-09-15) : LOC_FD6F9
;        finit CHR$, dont le lecteur a DEJA rendu son cadre (0F5C58h fait
;        pmdf +15) ; son -15 ne fait que le reconstituer. Le ret_str ci-dessous,
;        valide sur machine, n'a pas de pmdf. Ce qui compte est le bilan net.
;        Reference : C:\Claude\BASEXT\MODE-EMPLOI.md §6.1.
;
; ⛔ LE RESULTAT DOIT REMPLACER L'ARGUMENT SUR U, SANS LAISSER DE TROU (sinon la
;    concatenation « "["+TRIM$(...) » corrompt "["). Comme LEFT$ :
;      UCASE$/LCASE$ : transformation SUR PLACE ;
;      TRIM*         : sous-plage copiee AU SOMMET de la zone argument, U remonte ;
;      REPT$         : U ajuste pour finir ou finissait l'argument.
;
; ⛔ REPT$ fait DEUX eval (nombre puis chaine) : chacun abaisse BP de 15. On
;    RESTAURE BP au cadre du 1er eval (sv_bp1) avant de finaliser, comme MOD,
;    pour que le resultat soit au meme cadre que les fonctions a un seul argument.
;
; ⛔ X = point de reprise : on scanne avec Y ; pour une copie a deux pointeurs on
;    sauve X sur la pile SYSTEME. ORDRE IMPOSE : charger, CALL, VERIFIER, saisir.
;
;   PRINT "["+TRIM$ ("  ab  ")+"]"     [ab]
;   PRINT REPT$ (5,"*")                *****
;
;       xasm2026-4 STREXT.ASM -O -L -S -B -K
; ============================================================================

        include pce500.inc

eval:     equ   0EF26EH    ; expression complete ; abaisse BP de 15 ; bit 7 (BP+0)=chaine
dec2bin:  equ   0EFAD4H    ; nombre -> entier 24 bits en (BP+1)..(BP+3)
bin2dec:  equ   0EFB6FH    ; entier (BP+0)..(BP+3) -> nombre BASIC (entree RETF)
alloc:    equ   0EF0DDH    ; reserve BA octets sur U (U -= BA) ; carry = erreur 54

tk_uc:    equ   0C6H
tk_lc:    equ   0C7H
tk_tr:    equ   0C3H
tk_lt:    equ   0C4H
tk_rt:    equ   0C5H
tk_rp:    equ   0C8H
tk_in:    equ   0C2H       ; INSTR (rend un NOMBRE)
tk_sr:    equ   0C9H       ; SREPT$

err_syn:  equ   00AH       ; 10 Syntax error
err_type: equ   05AH       ; 90 Type mismatch
err_range: equ  021H       ; 33 Data out of range
err_buf:  equ   036H       ; 54 Buffer space exceeded

        org     0BF000H
        pre_on

; ============================================================================
; INSTALLATION
; ============================================================================
start:
        pushu   x
        pushu   i
        mv      x,(basptr)
        mv      a,[x+092H]
        cmp     a,00FH
        jrnz    deja_ext
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
        rc
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
; TABLES
; ============================================================================
kw_table:
        db      6,'UCASE$',tk_uc
        db      6,'LCASE$',tk_lc
        db      5,'TRIM$',tk_tr
        db      6,'LTRIM$',tk_lt
        db      6,'RTRIM$',tk_rt
        db      5,'REPT$',tk_rp
        db      6,'SREPT$',tk_sr
        db      5,'INSTR',tk_in
        db      0

disp_table:
        db      tk_uc, ucase_m3, ucase_m3/256, ucase_m3/65536+040H
        db      tk_lc, lcase_m3, lcase_m3/256, lcase_m3/65536+040H
        db      tk_tr, trim_m3,  trim_m3/256,  trim_m3/65536+040H
        db      tk_lt, ltrim_m3, ltrim_m3/256, ltrim_m3/65536+040H
        db      tk_rt, rtrim_m3, rtrim_m3/256, rtrim_m3/65536+040H
        db      tk_rp, rept_m3,  rept_m3/256,  rept_m3/65536+040H
        db      tk_sr, srept_m3, srept_m3/256, srept_m3/65536+040H
        db      tk_in, instr_m3, instr_m3/256, instr_m3/65536+040H
        db      0

; ============================================================================
; VARIABLES DU MODULE
; ============================================================================
sv_bp0:   db    0
sv_bp1:   db    0
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
old_kw:   db    0,0,0
old_disp: db    0,0,0

        end
