10 'TEST.BAS -- complement de BEXT.BAS : WPEEK et les cas limites
20 'BEXT.BAS eprouve LPOKE et LPEEK, litteraux puis variables.
30 'Celui-ci ajoute WPEEK, la valeur nulle et la borne des 20 bits.
40 CLS :CLEAR :AD=&BF300
50 '
60 'WPEEK ne prend que les deux premiers octets
70 LPOKE AD,&BFC15
80 PRINT HEX$ LPEEK AD;" ";HEX$ WPEEK AD
90 'attendu : BFC15 FC15
100 '
110 'les memes octets vus par PEEK : petit-boutien
120 PRINT HEX$ PEEK AD;" ";HEX$ PEEK (AD+1);" ";HEX$ PEEK (AD+2)
130 'attendu : 15 FC B
140 '
150 'une valeur nulle, et une valeur d'un seul octet
160 LPOKE AD,0,&0B
170 PRINT HEX$ LPEEK AD;" ";HEX$ LPEEK (AD+3)
180 'attendu : 0 B
190 '
200 'la borne : &FFFFF passe, au-dela dec2bin refuse (erreur 33)
210 LPOKE AD,&FFFFF
220 PRINT HEX$ LPEEK AD
230 'attendu : FFFFF
240 END
