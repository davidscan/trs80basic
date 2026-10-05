# ===================== the 56-bit double ====================================
# A DOUBLE IS THE MACHINE'S (since 2026-10-05, ruled that day; until then the
# host's 53-bit number): a 56-bit mantissa, and add, subtract, multiply,
# divide and the reader worked as the ROM works them (Farvour 0C70H-0E4CH,
# 0E65H-0F28H), their faults with them.
#
# THE PAYLOAD.  A double's number, in a value ("ND...") and in NV[]/VA[], is
#     <xd>          when the low three mantissa bits are zero
#     <xd> <k>      otherwise, k = 1..7 being those three bits
# xd is a host number: the value with its low three mantissa bits cleared,
# exact in the host's 53.  The value is xd plus k units of the 56th bit, away
# from zero.  num() and +0 read the leading number and get xd, which is right
# for every conversion to a single or an integer (they round on bits far
# above the three); a plain host number is a payload with k = 0, so an
# integer or a single needs nothing done to it to be a double.  Only what
# must be exact comes through here.
#
# Inside, a mantissa is three limbs M[2], M[1], M[0] of 8, 24 and 24 bits
# with the top bit set, and its exponent is the byte the machine keeps (80H
# for [.5,1), 0 for zero).  The 64-bit work value -- a mantissa over the
# guard byte -- is three limbs T[2], T[1], T[0] of 16, 24 and 24 bits.

# unpack payload p into M[]; returns the exponent byte, 0 for a zero (whose
# mantissa is left at one half, as ddiv needs); the sign goes to D5S
function dl(p, M,   i, x, k, e) {
    i = index(p, " ")
    if (i) { x = substr(p, 1, i - 1) + 0; k = substr(p, i + 1) + 0 } else { x = p + 0; k = 0 }
    D5S = (x < 0); if (D5S) x = -x
    if (x < FMIN) { D5S = 0; M[2] = 128; M[1] = 0; M[0] = 0; return 0 }
    e = sexp(x)
    x = x / (2 ^ (e - 56))                    # an integer below 2^56: exact
    M[2] = int(x / 281474976710656); x -= M[2] * 281474976710656
    M[1] = int(x / 16777216); M[0] = x - M[1] * 16777216 + k
    return e + 128
}

# pack: sign, mantissa, exponent byte -> payload.  Below the smallest byte the
# value is 0; past the largest it is ?OV (07B2H).
function dpk(sg, M, eb,   k, x) {
    if (eb <= 0) return "0"
    if (eb > 255) { raise(6); return "0" }
    k = M[0] % 8
    x = ((M[2] * 16777216 + M[1]) * 16777216 + (M[0] - k)) * (2 ^ (eb - 184))
    return (sg ? "-" : "") x (k ? " " k : "")
}

# the payload of a host number, as a string
function dnum(x) { return (x == 0) ? "0" : x "" }

function dneg(p) {
    p = p ""
    if (p + 0 == 0) return "0"
    return (substr(p, 1, 1) == "-") ? substr(p, 2) : "-" p
}

# p times a power of two (the low bits go with it)
function dscale(p, f,   i) {
    i = index(p, " ")
    return i ? (substr(p, 1, i - 1) * f) substr(p, i) : (p * f) ""
}

# -1, 0, 1 as p is below, equal to or above q
function dcmp(p, q,   x, y, i, j) {
    x = p + 0; y = q + 0
    if (x != y) return (x < y) ? -1 : 1
    i = index(p, " "); j = index(q, " ")
    i = i ? substr(p, i + 1) + 0 : 0; j = j ? substr(q, j + 1) + 0 : 0
    if (i == j) return 0
    return ((i < j) == (x >= 0)) ? -1 : 1
}

# mantissa -> work value, under guard byte g
function d_m2t(M, T, g) {
    T[0] = (M[0] % 65536) * 256 + g
    T[1] = int(M[0] / 65536) + (M[1] % 65536) * 256
    T[2] = int(M[1] / 65536) + M[2] * 256
}

# normalize the work value T[] (0CD8H-0D0DH), round on the guard's top bit
# (0D0EH-0D12H), pack
function d_norm(sg, T, eb,   g) {
    if (T[2] == 0 && T[1] == 0 && T[0] == 0) return "0"
    while (T[2] == 0) {                       # sixteen places at a time
        T[2] = int(T[1] / 256); T[1] = (T[1] % 256) * 65536 + int(T[0] / 256); T[0] = (T[0] % 256) * 65536
        eb -= 16
    }
    while (T[2] < 32768) {
        T[2] = T[2] * 2 + int(T[1] / 8388608)
        T[1] = (T[1] % 8388608) * 2 + int(T[0] / 8388608)
        T[0] = (T[0] % 8388608) * 2
        eb--
    }
    if (eb <= 0) return "0"
    g = T[0] % 256
    D5M[0] = int(T[0] / 256) + (T[1] % 256) * 65536
    D5M[1] = int(T[1] / 256) + (T[2] % 256) * 65536
    D5M[2] = int(T[2] / 256)
    if (g >= 128) {
        if (++D5M[0] >= 16777216) { D5M[0] = 0; if (++D5M[1] >= 16777216) { D5M[1] = 0; if (++D5M[2] >= 256) { D5M[2] = 128; eb++ } } }
    }
    return dpk(sg, D5M, eb)
}

# ADD (0C77H).  The value with the smaller exponent is shifted right to line
# up and one byte of what leaves it is kept (0D69H-0D8EH); 57 or more places
# apart, the larger value is the result (0CA1H CP 39H).  With like signs the
# sum is exact in the work value.  With unlike signs THE GUARD BYTE IS NOT
# SUBTRACTED: the seven mantissa bytes are (0D45H) and the byte shifted out
# is put under the difference as it is (0CB3H-0CB6H), so the result is high
# by twice that byte -- 1D16-.2# is one unit ABOVE 1D16, the ROM bug list's
# "1D16-0.20#".
function dadd(p, q,   ea, eb, sa, sb, d, w, pw, qw, i, g, t, c) {
    eb = dl(q, D5B); sb = D5S
    if (eb == 0) return p ""
    ea = dl(p, D5A); sa = D5S
    if (ea == 0) return q ""
    if (ea < eb) {
        for (i = 0; i < 3; i++) { t = D5A[i]; D5A[i] = D5B[i]; D5B[i] = t }
        t = ea; ea = eb; eb = t; t = sa; sa = sb; sb = t; p = q
    }
    d = ea - eb
    if (d >= 57) return p ""
    d_m2t(D5B, D5T, 0); D5T[3] = 0; D5T[4] = 0; D5T[5] = 0
    if (d) {
        w = int(d / 24); pw = 2 ^ (d % 24); qw = 16777216 / pw
        for (i = 0; i < 3; i++) D5T[i] = int(D5T[i + w] / pw) + (D5T[i + w + 1] % pw) * qw
    }
    d_m2t(D5A, D5U, 0)
    if (sa == sb) {
        c = 0
        for (i = 0; i < 3; i++) {
            t = D5U[i] + D5T[i] + c; c = 0
            if (i < 2 && t >= 16777216) { t -= 16777216; c = 1 }
            D5U[i] = t
        }
        if (D5U[2] >= 65536) {                 # a carry: everything right one, the exponent up one (0CC4H-0CC9H)
            D5U[0] = int(D5U[0] / 2) + (D5U[1] % 2) * 8388608
            D5U[1] = int(D5U[1] / 2) + (D5U[2] % 2) * 8388608
            D5U[2] = int(D5U[2] / 2)
            if (++ea > 255) { raise(6); return "0" }
        }
        return d_norm(sa, D5U, ea)
    }
    g = D5T[0] % 256
    if (D5T[2] == 0 && D5T[1] == 0 && D5T[0] < 256) { D5U[0] += g; return d_norm(sa, D5U, ea) }
    D5T[0] -= 2 * g                            # what the routine in effect takes away
    if (D5T[0] < 0) { D5T[0] += 16777216; if (--D5T[1] < 0) { D5T[1] += 16777216; D5T[2]-- } }
    for (i = 2; i > 0 && D5U[i] == D5T[i]; i--) ;
    if (D5U[i] < D5T[i]) {                      # a borrow: the difference is complemented, the sign turned (0D57H)
        for (i = 0; i < 3; i++) { t = D5U[i]; D5U[i] = D5T[i]; D5T[i] = t }
        sa = !sa
    }
    c = 0
    for (i = 0; i < 3; i++) {
        t = D5U[i] - D5T[i] - c; c = 0
        if (t < 0) { t += 16777216; c = 1 }
        D5U[i] = t
    }
    return d_norm(sa, D5U, ea)
}

# MULTIPLY (0DA1H).  The exponents are added and tested before the mantissas
# are worked (090AH-0930H), as in the single multiply: ?OV when the bytes
# less 80H reach 100H, whatever the mantissas would have done.  The product
# is exact to the work value's 64 bits and then rounded.
function dmul(p, q,   ea, eb, sa, sb, e, i, j, c) {
    ea = dl(p, D5A); sa = D5S
    eb = dl(q, D5B); sb = D5S
    if (ea == 0 || eb == 0) return "0"
    e = ea + eb - 128
    if (e >= 256) { raise(6); return "0" }
    for (i = 0; i < 6; i++) D5P[i] = 0
    for (i = 0; i < 3; i++) for (j = 0; j < 3; j++) D5P[i + j] += D5A[i] * D5B[j]
    for (i = 0; i < 5; i++) { c = int(D5P[i] / 16777216); D5P[i] -= c * 16777216; D5P[i + 1] += c }
    D5T[0] = D5P[2]; D5T[1] = D5P[3]; D5T[2] = D5P[4]
    return d_norm(sa != sb, D5T, e)
}

# DIVIDE (0DE5H): q is not 0 (the caller raised ?/0).  The exponent is
# settled first (0907H-0930H, then two added with no test), as in the single
# divide (smul/sdiv, p90), and two tests there go wrong for a double:
#   a divisor whose exponent byte is FFH -- 2^126 or more -- reads as a zero
#   operand, because the byte is complemented before the zero test at 0914H:
#   the quotient is 0;
#   the dividend is never tested for zero, so 0/Y is worked on a mantissa of
#   one half and an exponent byte of 0: for Y below .25 the quotient is a
#   small number, not 0 (the ROM bug list's "0/Y#").
function ddiv(p, q,   ea, eb, sa, sb, t, big, i, n, bit, c, acc) {
    eb = dl(q, D5B); sb = D5S
    ea = dl(p, D5A); sa = D5S
    if (eb == 255) return "0"
    t = ea - eb + 128
    if (t <= 1) return "0"
    if (t >= 257) { raise(6); return "0" }
    for (i = 2; i > 0 && D5A[i] == D5B[i]; i--) ;
    big = (D5A[i] >= D5B[i])
    if (t == 255 && big) return "0"
    if (t == 256) {
        if (!big) { raise(6); return "0" }
        t = 0
    }
    if (big) t++
    else { D5A[2] = D5A[2] * 2 + int(D5A[1] / 8388608); D5A[1] = (D5A[1] % 8388608) * 2 + int(D5A[0] / 8388608); D5A[0] = (D5A[0] % 8388608) * 2 }
    for (n = 0; n < 64; n++) {
        for (i = 2; i > 0 && D5A[i] == D5B[i]; i--) ;
        bit = (D5A[i] >= D5B[i])
        if (bit) {
            c = 0
            for (i = 0; i < 3; i++) { D5A[i] -= D5B[i] + c; c = 0; if (D5A[i] < 0) { D5A[i] += 16777216; c = 1 } }
        }
        acc = acc * 2 + bit
        if (n == 15) { D5T[2] = acc; acc = 0 }
        else if (n == 39) { D5T[1] = acc; acc = 0 }
        D5A[2] = D5A[2] * 2 + int(D5A[1] / 8388608); D5A[1] = (D5A[1] % 8388608) * 2 + int(D5A[0] / 8388608); D5A[0] = (D5A[0] % 8388608) * 2
    }
    D5T[0] = acc
    return d_norm(sa != sb, D5T, t)
}

# times ten (0E4DH): the value with its exponent up two, plus the value, then
# the exponent up one
function dmul10(p,   e, t) {
    if (p + 0 == 0) return "0"
    e = sexp(p + 0) + 128
    if (e + 2 > 255) { raise(6); return "0" }
    t = dadd(dscale(p, 4), p); if (E) return "0"
    if (sexp(t + 0) + 129 > 255) { raise(6); return "0" }
    return dscale(t, 2)
}

# THE READER for a double (0E65H-0F28H): the digits are gathered by times ten
# and plus the digit, then the value is divided or multiplied by ten once per
# place (0F18H, 0F0BH), each a rounded 56-bit step -- so a typed 89438606.6
# is the 56-bit value nearest that, where the host's 53 bits printed it back
# as 89438606.59999999.  t is the number's text: digits, an optional point,
# an optional exponent behind E or D; no sign.
function dread(t,   p, ex, fp, v, n, i, d, lead) {
    sub(/D/, "E", t)
    ex = 0
    if ((p = index(t, "E")) > 0) { ex = substr(t, p + 1) + 0; t = substr(t, 1, p - 1) }
    fp = ""
    if ((p = index(t, ".")) > 0) { fp = substr(t, p + 1); t = substr(t, 1, p - 1) }
    d = t fp; sub(/^0+/, "", d)
    lead = substr(d, 1, 15)                   # fifteen digits are exact in a host number
    v = dnum(lead + 0)
    for (i = 16; i <= length(d) && !E; i++) v = dadd(dmul10(v), substr(d, i, 1))
    n = ex - length(fp)
    for (i = 0; i < n && !E && v != "0"; i++) v = dmul10(v)
    for (i = 0; i > n && !E && v != "0"; i--) v = ddiv(v, "10")
    return v
}

# INT of a double from 32768 up (0B78H-0B9DH): the mantissa is shifted right
# until only the whole part is left, s = B8H less the exponent byte places.
# For a negative value the mantissa is first decremented (0BA0H) and the
# shifted result incremented (0D20H), which is the next whole number down
# unless the value was whole already.  THE FAULT: the shift routine begins by
# storing the mantissa's top byte from a register loaded before the decrement
# (0D69H LD (HL),C), so when the borrow reached that byte -- the six bytes
# below it all zero -- the borrow is undone and the result is one unit of the
# top byte too large in magnitude: INT(-44800#) is -45056 and INT(-65536#)
# is -66048, the ROM bug list's entry.  From B8H up every bit is whole.
function dint(p,   eb, sg, s, nz, u) {
    eb = dl(p, D5A); sg = D5S
    if (eb >= 184 || eb == 0) return p ""
    s = 184 - eb
    if (sg && D5A[1] == 0 && D5A[0] == 0) D5A[2]++
    else {
        if (s >= 48) { nz = (D5A[1] || D5A[0] || D5A[2] % (2 ^ (s - 48))); D5A[2] -= D5A[2] % (2 ^ (s - 48)); D5A[1] = 0; D5A[0] = 0 }
        else if (s >= 24) { u = 2 ^ (s - 24); nz = (D5A[0] || D5A[1] % u); D5A[1] -= D5A[1] % u; D5A[0] = 0 }
        else { u = 2 ^ s; nz = D5A[0] % u; D5A[0] -= nz }
        if (sg && nz) {                       # the next whole number down
            if (s >= 48) D5A[2] += 2 ^ (s - 48)
            else if (s >= 24) D5A[1] += 2 ^ (s - 24)
            else D5A[0] += 2 ^ s
            if (D5A[0] >= 16777216) { D5A[0] -= 16777216; D5A[1]++ }
            if (D5A[1] >= 16777216) { D5A[1] -= 16777216; D5A[2]++ }
        }
    }
    if (D5A[2] >= 256) { D5A[2] = 128; D5A[1] = 0; D5A[0] = 0; eb++ }
    return dpk(sg, D5A, eb)
}

# the eight stored bytes of a double (LSB first, the exponent last), and back
function dbytes(p,   e, sg, out) {
    e = dl(p, D5A); sg = D5S
    if (e == 0) return CHR[0] CHR[0] CHR[0] CHR[0] CHR[0] CHR[0] CHR[0] CHR[0]
    if (e > 255) { raise(6); return "" }
    return CHR[D5A[0] % 256] CHR[int(D5A[0] / 256) % 256] CHR[int(D5A[0] / 65536)] \
           CHR[D5A[1] % 256] CHR[int(D5A[1] / 256) % 256] CHR[int(D5A[1] / 65536)] \
           CHR[D5A[2] - 128 + (sg ? 128 : 0)] CHR[e]
}
function dfrombytes(s,   e, b) {
    e = ORD[substr(s, 8, 1)]
    if (e == 0) return "0"
    b = ORD[substr(s, 7, 1)]
    D5A[0] = ORD[substr(s, 1, 1)] + 256 * ORD[substr(s, 2, 1)] + 65536 * ORD[substr(s, 3, 1)]
    D5A[1] = ORD[substr(s, 4, 1)] + 256 * ORD[substr(s, 5, 1)] + 65536 * ORD[substr(s, 6, 1)]
    D5A[2] = (b >= 128) ? b : b + 128
    return dpk(b >= 128, D5A, e)
}
