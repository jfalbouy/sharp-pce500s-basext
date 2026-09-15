10 'MODDIAG.BAS --  MOD -    ?
20 'A  APRES   BASEXT (CALL &BF000).
30 'L   487    &BF000  &BF1E6.
40 CLS :CLEAR
50 R=MOD (17,5)
60 PRINT "MOD (17,5) = ";R;"    2"
70 '
80 '_ = &BF1DD :  A   2   ,  RIEN
90 '    . C     .
100 PRINT "A    ";HEX$ LPEEK &BF1DD
110 '
120 '_0 = &BF1E0,  UN  : PEEK,   LPEEK.
130 PRINT "BP ";PEEK &BF1E0
140 '
150 'CE QUE CELA DIRA
160 '  A  = 000011 (17) -> A  ,     
170 '          .
180 '  A  = 000000 -> A     ,  
190 '       2,     .
200 '
210 'L   ,    --      
220 '   . L      
230 ' : &BF1C0  &BF1E6,    -
240 '     BASIC.
250 PRINT "PRESS ANY KEY";
260 IF INKEY$ ="" THEN 260 ELSE PRINT
270 CLS :OPEN "F:RESULT.BAS" FOR OUTPUT AS #1
280 AD=&BF1C0:AF=&BF1F8:K=0
290 FOR I=AD TO AF
300 V=PEEK I:IF V>31 THEN V$=CHR$ V ELSE V$="."
310 L$=HEX$ I+" ("+STR$ V+" / "+HEX$ V+") : "+" ["+V$+"]"
320 PRINT L$
330 PRINT #1, L$
340 K=K+1:IF K<4 THEN 370
350 IF INKEY$ 1="" THEN 350
360 K=0:CLS
370 NEXT I
380 CLOSE :END
