# -*- coding: utf-8 -*-
r"""DWGLEMU.py -- execute l'instruction DWGL dans un interpreteur SC62015 reduit.

    python C:\Claude\BASEXT\essais\DWGLEMU.py

⛔ CE N'EST PAS UN ESSAI SUR MACHINE. Les trois entrees de la ROM sont SIMULEES
   selon leur contrat documente (BASEXT/MODE-EMPLOI.md §5 et §7.1) :
   eval (0EF26Eh), dec2bin (0EFAD4h) et iocs_call (0FFFE8h). Ce qui est
   reellement execute, ce sont les octets assembles de DWGL : la lecture des
   quatre arguments, la ponctuation, le tampon de libellés, les refus, et le
   compte de BP, de U, de S et de X. L'essai sur PC-E500S reste a faire
   (essais/DWGLTEST.BAS).

   Il a deja servi : a sa premiere execution, il a montre que « mv x,u »
   ecrasait le point de reprise du BASIC -- X revenait a l'interpreteur avec
   l'adresse de la pile U. Corrige par pushs/pops, comme INSTR.

DEUX CIBLES, et la seconde est celle qui compte :
   1. BASEXT.OBJ, le module autonome assemble en 0BF000h ;
   2. le bloc de BASEXTDR.OBJ, RELOGE comme l'installateur le reloge, puis
      execute a son adresse de destination -- c'est DWGL residant dans S1:.
"""
import re, sys, os

BASEXT = r"C:\Claude\BASEXT\src"
PILOTE = r"C:\Claude\BASEXT-DRV"


def symboles(lst):
    sym, dans = {}, False
    for l in open(lst, encoding='latin-1'):
        if l.startswith(' - Symbols -'):
            dans = True
        elif dans:
            m = re.match(r'^\s*([0-9A-F]{6})h\s+(\S+)\s*$', l.rstrip())
            if m:
                sym[m.group(2).lower()] = int(m.group(1), 16)
    return sym


def cible_module():
    """BASEXT.OBJ tel quel, en 0BF000h"""
    sym = symboles(os.path.join(BASEXT, 'BASEXT.lst'))
    obj = open(os.path.join(BASEXT, 'BASEXT.OBJ'), 'rb').read()
    charge = int.from_bytes(obj[8:11], 'little')
    return 'module autonome (0BF000h)', {charge: obj[16:]}, sym


def cible_pilote(dest=0x080018):
    """le bloc de BASEXTDR.OBJ, reloge par la table Kon comme le fait
       l'installateur, puis place a dest -- DWGL residant dans S1:"""
    sys.path.insert(0, os.path.join(PILOTE, 'outils'))
    import reloc
    sym = symboles(os.path.join(PILOTE, 'src', 'BASEXTDR.lst'))
    obj = open(os.path.join(PILOTE, 'src', 'BASEXTDR.OBJ'), 'rb').read()
    charge = int.from_bytes(obj[8:11], 'little')
    img = obj[16:]
    top, bas = sym['block_top'] - charge, sym['block_bottom'] - charge
    t0, t1 = sym['rel_table'] - charge, sym['rel_table_end'] - charge
    champs = reloc.decoder_kon(list(img[t0:t1]))
    bloc = bytearray(img[top:bas])
    ecart = (dest - sym['block_top']) & 0xFFFFFF
    for off, larg in champs:
        v = int.from_bytes(bloc[off:off + larg], 'little')
        v = (v + (ecart & ((1 << (8 * larg)) - 1))) & ((1 << (8 * larg)) - 1)
        bloc[off:off + larg] = v.to_bytes(larg, 'little')
    decale = dest - sym['block_top']
    sym = {k: v + decale for k, v in sym.items()}
    return ('pilote, bloc reloge en %05Xh (%d champs)' % (dest, len(champs)),
            {dest: bytes(bloc)}, sym)


EVAL, DEC2BIN, IOCS = 0x0EF26E, 0x0EFAD4, 0x0FFFE8
TXT = 0x0B0000          # le texte des arguments (tient lieu de ligne BASIC)
UTOP = 0x0BD000         # sommet de la pile U


class Arret(Exception):
    pass


class CPU:
    def __init__(self, images):
        self.MEM = bytearray(1 << 20)
        for adr, img in images.items():
            self.MEM[adr:adr + len(img)] = img
        self.INT = bytearray(256)
        self.A = self.B = self.IL = self.IH = 0
        self.X = self.Y = self.U = self.S = 0
        self.PC = self.PS = 0
        self.C = self.Z = 0
        self.pile = []
        self.iocs = []
        self.pre = False
        self.pas = 0

    def gr(self, c):
        return {0: self.A, 1: self.IL, 2: (self.B << 8) | self.A,
                3: (self.IH << 8) | self.IL, 4: self.X, 5: self.Y,
                6: self.U, 7: self.S}[c]

    def sr(self, c, v):
        if c == 0: self.A = v & 0xFF
        elif c == 1: self.IL = v & 0xFF
        elif c == 2: v &= 0xFFFF; self.B = v >> 8; self.A = v & 0xFF
        elif c == 3: v &= 0xFFFF; self.IH = v >> 8; self.IL = v & 0xFF
        elif c == 4: self.X = v & 0xFFFFF
        elif c == 5: self.Y = v & 0xFFFFF
        elif c == 6: self.U = v & 0xFFFFF
        elif c == 7: self.S = v & 0xFFFFF

    @property
    def BP(self):
        return self.INT[0xEC]

    def f8(self):
        b = self.MEM[(self.PS << 16) | self.PC]
        self.PC = (self.PC + 1) & 0xFFFF
        return b

    def f16(self):
        lo = self.f8()
        return lo | (self.f8() << 8)

    def f20(self):
        lo = self.f16()
        return lo | (self.f8() << 16)

    def ia(self, n):
        """adresse interne : absolue sous PRE, (BP+n) sinon"""
        return n if self.pre else (self.BP + n) & 0xFF

    def ptr(self, post, taille=1):
        mode, reg = post >> 5, post & 7
        base = self.gr(reg)
        if mode == 0:
            return base
        if mode == 1:
            self.sr(reg, base + taille)
            return base
        if mode == 2:
            base -= taille
            self.sr(reg, base)
            return base
        raise NotImplementedError('mode indirect %03b' % mode)

    def setZ(self, v):
        self.Z = 1 if (v & 0xFF) == 0 else 0

    def pousse(self, v, n):
        self.U = (self.U - n) & 0xFFFFF
        for i in range(n):
            self.MEM[self.U + i] = (v >> (8 * i)) & 0xFF

    def tire(self, n):
        v = int.from_bytes(self.MEM[self.U:self.U + n], 'little')
        self.U = (self.U + n) & 0xFFFFF
        return v

    def pas_a_pas(self):
        self.pas += 1
        if self.pas > 200000:
            raise Arret('boucle sans fin')
        op = self.f8()
        pre = self.pre
        self.pre = False
        if op in (0x30, 0x31, 0x32, 0x33):
            self.pre = True
            return
        self.pre_actif = pre
        M, I = self.MEM, self.INT
        # l'adressage interne de CETTE instruction
        self.pre = pre
        if op == 0x08: self.A = self.f8()
        elif op == 0x09: self.IL = self.f8(); self.IH = 0
        elif op == 0x0C: self.X = self.f20()
        elif op == 0x0D: self.Y = self.f20()
        elif op == 0x75: self.B = self.A
        elif op == 0xFD:
            p = self.f8(); self.sr(p >> 4, self.gr(p & 0xF))
        elif op == 0x80: self.A = I[self.ia(self.f8())]
        elif op == 0xA0: I[self.ia(self.f8())] = self.A
        elif op == 0x88: self.A = M[self.f20()]
        elif op == 0xA8: M[self.f20()] = self.A
        elif op == 0xD0:
            k = self.ia(self.f8()); I[k] = M[self.f20()]
        elif op == 0xD8:
            a = self.f20(); M[a] = I[self.ia(self.f8())]
        elif op == 0xCD:
            n = self.ia(self.f8()); v = self.f16()
            I[n] = v & 0xFF; I[(n + 1) & 0xFF] = v >> 8
        elif op == 0x90: self.A = M[self.ptr(self.f8())]
        elif op == 0xB0: M[self.ptr(self.f8())] = self.A
        elif op == 0x65:
            n = self.ia(self.f8()); m = self.f8(); self.setZ(I[n] & m)
        elif op == 0x60:
            n = self.f8(); r = self.A - n
            self.C = 1 if r < 0 else 0
            self.Z = 1 if (r & 0xFF) == 0 else 0
        elif op == 0x40:
            n = self.f8(); r = self.A + n
            self.C = 1 if r > 0xFF else 0
            self.A = r & 0xFF; self.setZ(self.A)
        elif op == 0x45:
            p = self.f8(); d, s = p >> 4, p & 0xF
            self.sr(d, (self.gr(d) + self.gr(s)) & 0xFFFFF)
        elif op == 0x7F:
            self.A |= I[self.ia(self.f8())]; self.setZ(self.A)
        elif op == 0x6C:
            p = self.f8() & 0xF; self.sr(p, self.gr(p) + 1)
            self.Z = 1 if self.gr(p) == 0 else 0
        elif op == 0x7C:
            p = self.f8() & 0xF; self.sr(p, self.gr(p) - 1)
            self.Z = 1 if self.gr(p) == 0 else 0
        elif op == 0xB4:
            # pushs x = B4 37 : S -= 3 puis X ecrit (nom donne par e500dasm)
            post = self.f8()
            if post != 0x37:
                raise NotImplementedError('B4 post %02X' % post)
            self.S = (self.S - 3) & 0xFFFFF
            for i in range(3):
                M[self.S + i] = (self.X >> (8 * i)) & 0xFF
        elif op == 0x94:
            # pops x = 94 27 : X relu puis S += 3
            post = self.f8()
            if post != 0x27:
                raise NotImplementedError('94 post %02X' % post)
            self.X = int.from_bytes(M[self.S:self.S + 3], 'little')
            self.S = (self.S + 3) & 0xFFFFF
        elif op == 0x2A: self.pousse((self.B << 8) | self.A, 2)
        elif op == 0x2B: self.pousse((self.IH << 8) | self.IL, 2)
        elif op == 0x2C: self.pousse(self.X, 3)
        elif op == 0x3A:
            v = self.tire(2); self.B = v >> 8; self.A = v & 0xFF
        elif op == 0x3B:
            v = self.tire(2); self.IH = v >> 8; self.IL = v & 0xFF
        elif op == 0x3C: self.X = self.tire(3)
        elif op == 0x9F: self.C = 0
        elif op == 0x97: self.C = 1
        elif op == 0x02: self.PC = self.f16()
        elif op == 0x12:
            n = self.f8(); self.PC = (self.PC + n) & 0xFFFF
        elif op == 0x13:
            n = self.f8(); self.PC = (self.PC - n) & 0xFFFF
        elif op in (0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F):
            n = self.f8()
            cond = {0x18: self.Z, 0x19: self.Z, 0x1A: not self.Z, 0x1B: not self.Z,
                    0x1C: self.C, 0x1D: self.C, 0x1E: not self.C, 0x1F: not self.C}[op]
            if cond:
                self.PC = ((self.PC + n) if op % 2 == 0 else (self.PC - n)) & 0xFFFF
        elif op == 0x04:
            t = self.f16(); self.pile.append(('p', self.PC, self.PS)); self.PC = t
        elif op == 0x05:
            t = self.f20()
            if t in (EVAL, DEC2BIN, IOCS):
                self.service(t)
                return
            self.pile.append(('l', self.PC, self.PS))
            self.PS = t >> 16; self.PC = t & 0xFFFF
        elif op in (0x06, 0x07):
            if not self.pile:
                raise Arret('retour')
            k, pc, ps = self.pile.pop()
            if k == 'fin':
                raise Arret('fin')
            self.PC = pc
            if op == 0x07:
                self.PS = ps
        else:
            raise NotImplementedError('opcode %02X en %01X:%04X'
                                      % (op, self.PS, self.PC - 1))
        self.pre = False

    # --- les trois services de la ROM, simules ---
    def service(self, t):
        if t == EVAL:
            self.s_eval()
        elif t == DEC2BIN:
            self.C = 0          # la valeur est deja en (BP+1)..(BP+3)
        else:
            self.s_iocs()

    def cadre(self, n=15):
        self.INT[0xEC] = (self.BP - n) & 0xFF

    def s_eval(self):
        """lit un terme a X : nombre decimal ou &hexa, ou chaine entre guillemets"""
        M = self.MEM
        while M[self.X] == 0x20:
            self.X += 1
        c = chr(M[self.X])
        if c == '"':
            self.X += 1
            deb = self.X
            while M[self.X] != 0x22:
                self.X += 1
            s = bytes(M[deb:self.X])
            self.X += 1
            self.U = (self.U - len(s)) & 0xFFFFF
            M[self.U:self.U + len(s)] = s
            self.cadre()
            bp = self.BP
            self.INT[bp] = 0x80
            for i in range(3):
                self.INT[(bp + 1 + i) & 0xFF] = (self.U >> (8 * i)) & 0xFF
            self.INT[(bp + 4) & 0xFF] = len(s)
            self.C = 0
            return
        chiffres = '0123456789ABCDEFabcdef' if c == '&' else '0123456789'
        if c == '&' or c.isdigit():
            if c == '&':
                self.X += 1
            deb = self.X
            while chr(M[self.X]) in chiffres:
                self.X += 1
            v = int(bytes(M[deb:self.X]).decode(), 16 if c == '&' else 10)
            self.cadre()
            bp = self.BP
            self.INT[bp] = 0x00
            for i in range(3):
                self.INT[(bp + 1 + i) & 0xFF] = (v >> (8 * i)) & 0xFF
            self.C = 0
            return
        self.A = 0x16       # Illegal function call, comme eval en echec
        self.C = 1

    def s_iocs(self):
        bl, bh, cl, ch = self.INT[0xD4], self.INT[0xD5], self.INT[0xD6], self.INT[0xD7]
        n = self.A
        lib = []
        p = self.X
        for _ in range(n):
            d = p
            while self.MEM[p] != 0xFF:
                p += 1
            lib.append(bytes(self.MEM[d:p]).decode('latin-1'))
            p += 1
        self.iocs.append(dict(il=self.IL, cl=cl, ch=ch, bl=bl, bh=bh,
                              a=n, b=self.B, lib=lib))
        self.C = 1          # 058h ne fixe PAS la retenue : on la laisse armee expres


def essai(texte, bp=0xBE):
    c = CPU(IMAGES)
    c.MEM[TXT:TXT + len(texte)] = texte.encode('latin-1')
    c.MEM[TXT + len(texte)] = 0x0D
    c.INT[0xEC] = bp
    c.U = UTOP
    c.S = 0x0BE000
    c.X = TXT
    c.PS = sym['dwgl'] >> 16
    c.PC = sym['dwgl'] & 0xFFFF
    c.pile.append(('fin', 0, 0))
    try:
        while True:
            c.pas_a_pas()
    except Arret:
        pass
    return c


def montre(nom, texte, c):
    reste = bytes(c.MEM[c.X:c.X + 6]).decode('latin-1').replace('\r', '<CR>')
    etat = 'CY=%d A=%02X' % (c.C, c.A)
    cadre = 'BP=%02X %s U %s' % (c.BP, 'rendu' if c.BP == 0xBE else 'FAUX',
                                 'rendue' if c.U == UTOP else 'FAUSSE %05X' % c.U)
    print('%-10s %-44s %-11s %-26s X->%r' % (nom, 'DWGL ' + texte, etat, cadre, reste))
    for ap in c.iocs:
        print('%12s il=%02X (cl,ch)=(%d,%d) (bl,bh)=(%d,%d) A=%d B=%02X  %s'
              % ('', ap['il'], ap['cl'], ap['ch'], ap['bl'], ap['bh'], ap['a'],
                 ap['b'], ' '.join('[%s]' % s for s in ap['lib'])))
    return c


ok = True


def verifie(cond, quoi):
    global ok
    if not cond:
        ok = False
        print('   ECHEC : ' + quoi)



def tests():
    print('=== 1. le trace nominal ===')
    t = '0,3,0,"BASIC ,DUMPM ,DRIVER,TRDOS ,SUITE "'
    c = montre('nominal', t, essai(t))
    verifie(c.C == 0, 'retenue claire attendue (la 058h la laisse armee)')
    verifie(c.BP == 0xBE and c.U == UTOP, 'BP et U rendus')
    verifie(len(c.iocs) == 1, 'un appel IOCS')
    a = c.iocs[0]
    verifie((a['il'], a['cl'], a['ch']) == (0x58, 0, 0), 'commande 58h du device 0')
    verifie((a['bl'], a['bh'], a['a'], a['b']) == (0, 3, 5, 0),
            'colonne 0, ligne 3, 5 cases, B=0')
    verifie(a['lib'] == ['BASIC ', 'DUMPM ', 'DRIVER', 'TRDOS ', 'SUITE '], 'les cinq libelles')
    verifie(c.MEM[c.X] == 0x0D, 'X rendu sur la fin de ligne')
    verifie(c.S == 0x0BE000, 'pile S rendue')

    print('')
    print('=== 2. le tag : parentheses (bit 0) et ligne gardee (bit 7) ===')
    for t, att in (('8,2,1,"UN,DEUX"', (8, 2, 2, 1)),
                   ('16,3,&81,"MILIEU,DROITE"', (16, 3, 2, 0x81))):
        c = montre('tag', t, essai(t))
        a = c.iocs[0]
        verifie((a['bl'], a['bh'], a['a'], a['b']) == att, 'parametres de ' + t)

    print('')
    print('=== 3. libelle court, libelle trop long, une seule case ===')
    t = '0,3,0,"A,TROPLONGPOURSIX,C"'
    c = montre('longueurs', t, essai(t))
    verifie(c.iocs[0]['lib'] == ['A', 'TROPLONGPOURSIX', 'C'],
            'la ROM complete et tronque elle-meme')
    t = '0,0,0,"SEUL"'
    c = montre('une case', t, essai(t))
    verifie(c.iocs[0]['a'] == 1 and c.iocs[0]['lib'] == ['SEUL'], 'une seule case')

    print('')
    print('=== 4. les refus ===')
    cas = [('0,4,0,"A"', 0x21, 'ligne >= 4'),
           ('1,3,0,"A,B,C,D,E"', 0x21, 'colonne + 8 x cases > 40'),
           ('0,3,0,"A,B,C,D,E,F"', 0x21, 'plus de cinq cases'),
           ('0,3,0,"' + 'X' * 48 + '"', 0x21, 'chaine de 48 caracteres'),
           ('0,3,0,""', 0x5A, 'chaine vide'),
           ('0,3,0,5', 0x5A, 'ce n est pas une chaine'),
           ('0,3;0,"A"', 0x0A, 'virgule manquante'),
           ('0,3,0', 0x0A, 'virgule manquante avant le 4e argument'),
           ('0,3,0,UNDEF', 0x16, 'eval en echec')]
    for t, code, quoi in cas:
        c = montre('refus', t, essai(t))
        verifie(c.C == 1, 'retenue armee : ' + quoi)
        verifie(c.A == code, 'erreur %02X attendue (%s), obtenue %02X' % (code, quoi, c.A))
        verifie(c.BP == 0xBE, 'BP rendu : ' + quoi)
        verifie(len(c.iocs) == 0, 'aucun trace : ' + quoi)

    print('')
    print('=== 5. cas limites acceptes ===')
    t = '0,3,0,"' + 'X' * 47 + '"'
    c = montre('47 car.', t, essai(t))
    verifie(len(c.iocs) == 1, 'une chaine de 47 caracteres passe')
    t = '0,3,0,"A,B,C,D,E"'
    c = montre('5 cases', t, essai(t))
    verifie(c.iocs[0]['a'] == 5, 'cinq cases en colonne 0')
    t = ' 0 , 3 , 0 , "A,B"'
    c = montre('espaces', t, essai(t))
    verifie(len(c.iocs) == 1 and c.iocs[0]['a'] == 2, 'espaces autour des virgules')

    print('')
    print('=== 6. le tampon ne deborde pas ===')
    c = essai('0,3,0,"' + 'X' * 47 + '"')
    deb = sym['dw_buf']
    fin = deb + 48
    apres = [i for i in range(fin, fin + 8) if c.MEM[i] != 0]
    print('dw_buf %05X..%05X ; octets non nuls au-dela : %s'
          % (deb, fin - 1, apres or 'aucun'))
    verifie(not apres, 'ecriture au-dela du tampon')



ok = True
for fab in (cible_module, cible_pilote):
    nom, IMAGES, sym = fab()
    print('')
    print('############  ' + nom + '  ############')
    print('')
    tests()

print('')
print('*** TOUT PASSE ***' if ok else '*** DES ESSAIS ONT ECHOUE ***')
sys.exit(0 if ok else 1)
