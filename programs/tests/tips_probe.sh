#!/bin/sh
# tips_probe.sh -- the trs-80.com Level II tips page, probed not reasoned.
# Source: https://www.trs-80.com/sub-tips-level2.htm (Goldklang).  The 78
# numbered tips are the page's top half in order, numbered as the 2026-09-05
# tally numbered them (STATUS.local.md "PERIOD TIPS/TRICKS COMPATIBILITY");
# B1-B18 are the page's later BASIC sections, first measured 2026-09-11.
# Every probe is a batch program with a DECLARED expected output and a
# category; the tally is computed from what actually ran.  Exit 1 if any
# probe's output differs from its declaration, so a change in behaviour --
# a tip coming alive, or dying -- shows up as a mismatch, never silently.
#   W  works as the tip says            K  the POKE/PEEK is inert, a keyword does it
#   D  runs harmlessly, does nothing    X  gives an answer that disagrees with us
#   E  errors out
# Run from the repo root:  sh programs/tests/tips_probe.sh   (-v shows every line)
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
tmp=$(mktemp) || exit 2
lp="$tmp.lp"
verbose=0; [ "$1" = "-v" ] && verbose=1
nW=0; nK=0; nD=0; nX=0; nE=0; bad=0; n=0
tally() { case "$1" in W) nW=$((nW+1));; K) nK=$((nK+1));; D) nD=$((nD+1));; X) nX=$((nX+1));; E) nE=$((nE+1));; esac; }
# probe ID CAT "label" "stdin" "expected output" "program" [env assignments]
probe() {
    id=$1; cat=$2; label=$3; in=$4; want=$5; prog=$6; envs=$7
    printf '%s\n' "$prog" > "$tmp"; rm -f "$lp"
    got=$(printf '%s' "$in" | env TRS80_PRINTER="$lp" $envs "$here/basic" "$tmp" 2>&1)
    [ -s "$lp" ] && got="$got|LP:$(cat "$lp")"
    case "$id" in *x) counted=0;; *) counted=1; n=$((n+1));; esac
    if [ "$got" = "$want" ]; then
        [ $counted = 1 ] && tally "$cat"; [ $verbose = 1 ] && printf '%-4s %s  %s\n' "$id" "$cat" "$label"
    else
        bad=$((bad+1)); printf '%-4s MISMATCH  %s\n   expected: %s\n   got:      %s\n' "$id" "$label" "$want" "$got"
    fi
}
nl='
'

# ---- System status / ID -----------------------------------------------------
probe 1  W "Model I: PEEK(293)<>73"            "" "-1 " '10 PRINT PEEK(293)<>73'
probe 2  W "Model II: PEEK(125)=2"             "" " 0 " '10 PRINT PEEK(125)=2'
probe 3  W "Model III: PEEK(293)=73"           "" " 0 " '10 PRINT PEEK(293)=73'
probe 4  W "Model 4/4D: PEEK(125)=4"           "" " 0 " '10 PRINT PEEK(125)=4'
probe 5  W "Model 4P: PEEK(125)=5"             "" " 0 " '10 PRINT PEEK(125)=5'
probe 6  W "Model 12: PEEK(125)=12"            "" " 0 " '10 PRINT PEEK(125)=12'
# 7: 37ECH is the floppy controller status register.  RULED 2026-09-11 (user):
# stay at 255 = "no expansion interface".  The 14 corpus listings that read
# it treat "not 255" as "disk present" and go on to CMD, DEF USR from disk or
# a not-ready wait loop, so reporting an interface would push them off the
# branch that runs here.  Dead and deliberate, not wrong.
probe 7  D "no expansion interface: PEEK(14316)=255 (deliberate: keeps disk probes on their cassette branch)" "" "-1 " '10 PRINT PEEK(14316)=255'
probe 8  X "not Disk BASIC: PEEK(16549)<66 (66 is authentic; the page's boundary is off)" "" " 0 " '10 PRINT PEEK(16549)<66'
probe 9  D "TRSDOS 6.1: PEEK(&H85)=&H61"       "" " 0 " '10 PRINT PEEK(&H85)=&H61'
probe 10 D "TRSDOS 6.2: PEEK(&H85)=&H62"       "" " 0 " '10 PRINT PEEK(&H85)=&H62'
probe 11 D "TRSDOS 6.3: PEEK(&H85)=&H63"       "" " 0 " '10 PRINT PEEK(&H85)=&H63'
probe 12 W "lowercase mod: POKE 15360,1 reads 1" "" " 1 " '10 PRINT@128,"";:POKE 15360,1:X=PEEK(15360):PRINT X'
probe 13 D "extended error messages flag (PEEK(124) AND &H40)" "" "-1 " '10 PRINT (PEEK(124) AND &H40)<>0'
probe 14 D "full file access flag (PEEK(119) AND 128)" "" "-1 " '10 PRINT (PEEK(119) AND 128)<>0'
probe 15 D "special character mode PEEK(&HB94)<>0" "" "-1 " '10 PRINT PEEK(&HB94)<>0'
probe 16 D "keyboard case lock PEEK(16409)"    "" " 255 " '10 PRINT PEEK(16409)'
# ---- Reset button pokes ------------------------------------------------------
probe 17 D "RESET = NEW"       "" "OK" '10 POKE 16830,195:POKE 16831,73:POKE 16832,27:PRINT "OK"'
probe 18 D "RESET = RUN"       "" "OK" '10 POKE 16830,195:POKE 16831,163:POKE 16832,30:PRINT "OK"'
probe 19 D "RESET = SYSTEM"    "" "OK" '10 POKE 16830,195:POKE 16831,178:POKE 16832,2:PRINT "OK"'
probe 20 D "RESET disabled"    "" "OK" '10 POKE 16830,201:PRINT "OK"'
probe 21 D "RESET restarts a SYSTEM program" "" "OK" '10 POKE 16830,195:POKE 16831,PEEK(16607):POKE 16832,PEEK(16608):PRINT "OK"'
probe 22 D "jump to an address on RESET (16391/2)" "" "OK" '10 POKE 16391,0:POKE 16392,125:PRINT "OK"'
# 23 as printed uses the compressed form POKE16812,195 -- keyword-adjacent
# source is out of scope by ruling (basclean de-compresses it), so as written
# it is ?SN.  RULED 2026-09-11 (user): "dead in spirit if not law" -- the
# spaced form is what counts in the 78 (D); the as-printed form is pinned
# below as 23x, uncounted (an id ending in x is never tallied).
probe 23x E "disable RESET and BREAK (packed routine at 4007H) -- as printed, POKE16812 compressed" "" "?SN ERROR IN 30" "10 QQ\$=CHR\$(42)+CHR\$(164)+CHR\$(64)+CHR\$(43)+CHR\$(195)+CHR\$(30)+CHR\$(29)${nl}20 Q=VARPTR(QQ\$):Q1=PEEK(Q+1):Q2=PEEK(Q+2)${nl}30 POKE16812,195:POKE16813,Q1:POKE16814,Q2${nl}40 PRINT \"OK\""
probe 23 D "disable RESET and BREAK (packed routine at 4007H), spaced" "" "OK" "10 QQ\$=CHR\$(42)+CHR\$(164)+CHR\$(64)+CHR\$(43)+CHR\$(195)+CHR\$(30)+CHR\$(29)${nl}20 Q=VARPTR(QQ\$):Q1=PEEK(Q+1):Q2=PEEK(Q+2)${nl}30 POKE 16812,195:POKE 16813,Q1:POKE 16814,Q2${nl}40 PRINT \"OK\""
probe 24 D "disable LIST (16863..)"   "" "20 LIST 20" "10 POKE 16863,95:POKE 16864,204:POKE 16865,6${nl}20 LIST 20"
probe 25 D "disable SYSTEM (16866..)" "" "OK" '10 POKE 16866,195:POKE 16867,204:POKE 16868,6:PRINT "OK"'
# ---- Break key pokes ---------------------------------------------------------
probe 26 D "BREAK disabled (L2): POKE 16396,23"   "" "OK" '10 POKE 16396,23:PRINT "OK"'
probe 27 D "BREAK enabled (L2): POKE 16396,201"   "" "OK" '10 POKE 16396,201:PRINT "OK"'
probe 28 D "BREAK disabled (DOS): POKE 17170/1"   "" "OK" '10 POKE 17170,175:POKE 17171,201:PRINT "OK"'
probe 29 D "BREAK re-enabled (DOS)"               "" "OK" '10 POKE 17170,195:POKE 17171,164:PRINT "OK"'
probe 30 D "BREAK = reverse tab"                  "" "OK" '10 POKE 16396,10:PRINT "OK"'
probe 31 D "BREAK = space"                        "" "OK" '10 POKE 16396,15:PRINT "OK"'
probe 32 D "BREAK = reverse stars"                "" "OK" '10 POKE 16396,47:PRINT "OK"'
probe 33 D "BREAK = SHIFT-@"                      "" "OK" '10 POKE 16396,62:POKE 16397,96:POKE 16398,201:PRINT "OK"'
probe 34 D "BREAK = freeze"                       "" "OK" '10 POKE 16396,49:PRINT "OK"'
probe 35 D "BREAK = READY"                        "" "OK" '10 POKE 16396,118:PRINT "OK"'
probe 36 D "BREAK = U, shift = V"                 "" "OK" '10 POKE 16396,133:PRINT "OK"'
probe 37 D "BREAK disabled, shift-BREAK ok"       "" "OK" '10 POKE 16396,165:PRINT "OK"'
probe 38 D "BREAK = SN ERROR"                     "" "OK" '10 POKE 16396,227:PRINT "OK"'
probe 39 D "BREAK = MEMORY SIZE"                  "" "OK" '10 POKE 16396,228:PRINT "OK"'
probe 40 D "BREAK reinitialises BASIC"            "" "OK" '10 POKE 16396,199:PRINT "OK"'
probe 41 D "BREAK disabled (NewDOS 2.1): POKE 23461,0" "" "OK" '10 POKE 23461,0:PRINT "OK"'
probe 42 D "BREAK disabled (TRSDOS 2.3): POKE 23886,0" "" "OK" '10 POKE 23886,0:PRINT "OK"'
probe 43 D "BREAK -> SHIFT-BREAK"                 "" "OK" '10 POKE 16396,165:PRINT "OK"'
probe 44 D "BREAK -> RESET"                       "" "OK" '10 POKE 16396,233:PRINT "OK"'
probe 45 D "BREAK enabled flag (PEEK(124) AND &H10)" "" "-1 " '10 PRINT (PEEK(124) AND &H10)<>0'
# ---- Keyboard ----------------------------------------------------------------
probe 46 D "disable keyboard POKE 16405,0 (INPUT still reads)" "X${nl}" "? X${nl}GOT X" "10 POKE 16405,0:INPUT A\$:PRINT \"GOT \";A\$"
probe 47 D "enable keyboard POKE 16405,1"          "" "OK" '10 POKE 16405,1:PRINT "OK"'
probe 48 W "any key pressed: PEEK(14463)=0 false with A held" "A${nl}" " 0 " '10 PRINT PEEK(14463)=0'
probe 49 W "any non-SHIFT key: PEEK(14591)=0 false with A held" "A${nl}" " 0 " '10 PRINT PEEK(14591)=0'
probe 50 D "full file access ON: POKE 119"        "" "OK" '10 POKE 119,(PEEK(119) OR &H80):PRINT "OK"'
probe 51 D "full file access OFF: POKE 119"       "" "OK" '10 POKE 119,(PEEK(119) AND &H7F):PRINT "OK"'
probe 52 D "extended errors ON: POKE 124"         "" "OK" '10 POKE 124,(PEEK(124) OR &H40):PRINT "OK"'
probe 53 W "arrow row PEEK(14400): space held reads 128" " ${nl}" " 128 " '10 PRINT PEEK(14400)'
probe 54 W "detailed row PEEK(14537): space held reads 128" " ${nl}" " 128 " '10 PRINT PEEK(14537)'
# ---- Video -------------------------------------------------------------------
probe 55 D "disable display POKE 16413,0"         "" "VISIBLE" '10 POKE 16413,0:PRINT "VISIBLE"'
probe 56 D "enable display POKE 16413,7"          "" "OK" '10 POKE 16413,7:PRINT "OK"'
probe 57 D "special character set via &HB94"      "" "OK" '10 POKE &HB94,(PEEK(&HB94) OR 8):PRINT "OK"'
probe 58 D "three-line scroll protect via &HB94"  "" "OK" '10 POKE &HB94,(PEEK(0) OR 8):PRINT "OK"'
probe 59 D "change cursor character POKE &HB98"   "" "OK" '10 POKE &HB98,42:PRINT "OK"'
probe 60 W "cursor position PEEK(16416/7) = 3C00H + cursor" "" " 70 " '10 PRINT@70,"";:P=PEEK(16416)+256*PEEK(16417)-15360:PRINT P'
# ---- Time / date, Model 4 --------------------------------------------------
probe 61 W "Model I time/date PEEK(16449..16454) from the host clock" "" "-1 " '10 PRINT PEEK(16454)>=1 AND PEEK(16454)<=12 AND PEEK(16451)<=23 AND PEEK(16449)<=59'
probe 62 D "Model III time/date PEEK(16919..16924)" "" " 255  255 " '10 PRINT PEEK(16919);PEEK(16924)'
probe 63 D "Model 4 speed-up (16912, OUT 235)"   "" "OK" '10 X=PEEK(16912):X=X OR 64:POKE 16912,X:OUT 235,X:PRINT "OK"'
# ---- Printer -----------------------------------------------------------------
probe 64 D "screen printer OUT 254,255"          "" "OK" '10 OUT 254,255:PRINT "OK"'
probe 65 W "printer line counter PEEK(16425) after two LPRINT lines" "" " 2 |LP:A${nl}B" '10 LPRINT "A":LPRINT "B":PRINT PEEK(16425)'
probe 66 W "print head position PEEK(16539) after LPRINT \"ABC\";" "" " 3 |LP:ABC" '10 LPRINT "ABC";:PRINT PEEK(16539)'
probe 67 W "lines per page + 1: PEEK(16424) = 67" "" " 67 " '10 PRINT PEEK(16424)'
probe 68 W "printer status PEEK(14312)=63 ready" "" " 63 " '10 PRINT PEEK(14312)'
probe 69 D "JKL off POKE 16422,216"              "" "OK" '10 POKE 16422,216:PRINT "OK"'
# ---- Keyword tips ------------------------------------------------------------
probe 70 W "start AUTO by POKE 16609,1: flag reads back, AUTO fires at the next READY (t33)" "" " 1 " '10 POKE 16609,1:PRINT PEEK(16609)'
probe 71 W "AUTO increment by POKE 16612/3 reads back" "" " 7 " '10 POKE 16612,7:POKE 16613,0:PRINT PEEK(16612)+256*PEEK(16613)'
probe 72 D "disable LIST method 1 (16863: 145,25,26)" "" "20 LIST 20" "10 POKE 16863,145:POKE 16864,25:POKE 16865,26${nl}20 LIST 20"
probe 73 D "disable LIST method 2 (16863: 195,114,0)" "" "20 LIST 20" "10 POKE 16863,195:POKE 16864,114:POKE 16865,0${nl}20 LIST 20"
probe 74 D "disable LLIST POKE 16422,103 (LLIST still prints)" "" "|LP:10 POKE 16422,103:POKE 16423,0:LLIST 10" '10 POKE 16422,103:POKE 16423,0:LLIST 10'
probe 75 W "RND seed POKE 16554-6 = 5,10,15 gives 80 78 91 88 70 91 25 30" "" " 80  78  91  88  70  91  25  30 " "10 POKE 16554,5:POKE 16555,10:POKE 16556,15${nl}20 FOR I=1 TO 8:PRINT RND(100);:NEXT:PRINT"
probe 76 W "TRON by POKE 16667,1 traces the next line" "" "<20>T" "10 POKE 16667,1${nl}20 PRINT \"T\""
probe 77 W "TROFF by POKE 16667,0 stops the trace" "" "<20>T${nl}X" "10 POKE 16667,1${nl}20 POKE 16667,0:PRINT \"T\"${nl}30 PRINT \"X\""
probe 78 E "recover after NEW: POKE 17130,1 : SYSTEM" "" "?SN ERROR IN 10" '10 POKE 17130,1:SYSTEM'
n78=$n; bad78=$bad; W78=$nW; K78=$nK; D78=$nD; X78=$nX; E78=$nE

# ---- B: the page's BASIC sections (not in the 78) ----------------------------
probe B1 W "screen print via VARPTR alias (Jay Reso): LPRINT a string pointed at a screen row" "" \
"HELLO SCREEN${nl}ROW TWO|LP:HELLO SCREEN                                                    ${nl}ROW TWO                                                         " \
"10 PRINT@0,\"HELLO SCREEN\":PRINT@64,\"ROW TWO\"${nl}20 DIM S\$(15):FOR T=0 TO 1:S\$(T)=\"\":POKE VARPTR(S\$(T)),64:POKE VARPTR(S\$(T))+1,(T*64+15360) AND 255:POKE VARPTR(S\$(T))+2,(T*64+15360)/256:NEXT${nl}30 FOR T=0 TO 1:LPRINT S\$(T):NEXT"
probe B2 W "super sort (Dettman): swap two strings by exchanging descriptor bytes" "" "ZEBRA APPLE" \
"10 DIM A\$(2):A\$(1)=\"APPLE\":A\$(2)=\"ZEBRA\"${nl}20 FOR Z=0 TO 2:A1=PEEK(VARPTR(A\$(1))+Z):A2=PEEK(VARPTR(A\$(2))+Z):POKE (VARPTR(A\$(1))+Z),A2:POKE (VARPTR(A\$(2))+Z),A1:NEXT Z${nl}30 PRINT A\$(1);\" \";A\$(2)"
probe B3 W "set MEMORY SIZE from BASIC: POKE 16561/2 then CLEAR" "" " 60000 -1 " \
"10 ME=60000:MS=INT(ME/256):LS=ME-(MS*256):POKE 16561,LS:POKE 16562,MS:CLEAR 50${nl}20 PRINT PEEK(16561)+256*PEEK(16562);${nl}30 A\$=\"XYZ\":PRINT VARPTR(A\$)<=60000"
probe B4 W "set a USR routine for DOS and Level II (PEEK(16396) picks 16526)" "" \
" 16526 ${nl}USR slot=0 entry=32000 arg=0${nl}USR STUB: 1 CALL NOT EXECUTED (7D00H x1): no Z80 core, each returned its argument; TRS80_USR=strict raises ?FC instead" \
"10 A=PEEK(16396):IF A=195 THEN AD=23316 ELSE AD=16526${nl}20 POKE AD,0:POKE AD+1,125:PRINT AD${nl}30 X=USR(0)" "TRS80_USR_TRACE=1"
probe B5 W "poking above 32767 with a negative address" "" " 0  7 " '10 POKE -1,0:PRINT PEEK(-1);:POKE -1,7:PRINT PEEK(-1)'
probe B6 D "renumber by POKEing line numbers into the program image (image is read-only)" "" \
"A${nl}B${nl}10 PRINT \"A\"${nl}20 PRINT \"B\"${nl}30 P=17129:FOR L=1 TO 9000:IF PEEK(P+1)>0 THEN POKE P+3,PEEK(P+3)+125:P=PEEK(P)+256*PEEK(P+1):NEXT${nl}40 LIST" \
"10 PRINT \"A\"${nl}20 PRINT \"B\"${nl}30 P=17129:FOR L=1 TO 9000:IF PEEK(P+1)>0 THEN POKE P+3,PEEK(P+3)+125:P=PEEK(P)+256*PEEK(P+1):NEXT${nl}40 LIST"
probe B7 D "append two programs by POKEing 16548/9 (pointer is read-only)" "" " 233 " '10 POKE 16548,0:PRINT PEEK(16548)'
probe B8 W "start and end of program PEEK(16548/9), PEEK(16633/4)" "" " 17129  17181 " '10 PRINT PEEK(16548)+256*PEEK(16549);PEEK(16633)+256*PEEK(16634)'
probe B9 W "current line number PEEK(16546/7)"   "" " 20 " "10 X=1${nl}20 PRINT PEEK(16546)+256*PEEK(16547)"
probe B10 W "current cursor character PEEK(16418), and POKE 16418,0 hides it" "" " 176  0 " '10 PRINT PEEK(16418);:POKE 16418,0:PRINT PEEK(16418)'
probe B11 W "get your 48K: POKE 16561/2 = 255 then CLEAR 50" "" " 65535 " '10 POKE 16561,255:POKE 16562,255:CLEAR 50:PRINT PEEK(16561)+256*PEEK(16562)'
probe B12 W "(X,Y) <-> PRINT@ conversion"        "" " 133  10  6 " '10 X=10:Y=7:P=INT(Y/3)*64+INT(X/2):Y2=3*INT(P/64):X2=2*(P-64*Y2/3):PRINT P;X2;Y2'
probe B13 D "cause a reset: POKE 16415,5"         "" "OK" '10 POKE 16415,5:PRINT "OK"'
probe B14 D "route LPRINT to video: POKE 16422,88:POKE 16423,4" "" "|LP:TO VIDEO?" '10 POKE 16422,88:POKE 16423,4:LPRINT "TO VIDEO?"'
probe B15 D "route video to printer: POKE 16414,141:POKE 16415,5" "" "STILL VIDEO" '10 POKE 16414,141:POKE 16415,5:PRINT "STILL VIDEO"'
probe B16 D "change the cursor (AWFUL routine at 32512)" "" "OK" \
"20 FOR X=32512 TO 32522:READ A:POKE X,A:NEXT${nl}30 POKE 16414,0:POKE 16415,127${nl}40 DATA 205,88,4,229,42,32,64,54${nl}50 DATA 42${nl}60 DATA 225,201${nl}70 PRINT \"OK\""
probe B17 W "voice control: INP(255) reads 127, no sound (was ?BS until 2026-09-11)" "" " 127 " '10 PRINT INP(255)'
probe B18 D "screen graphics hard copy (PEEKs the screen, LPRINTs #)" "" "|LP:#  " \
"10 SET(0,0):SET(3,2)${nl}20 X=15360:A=1:B=2:FOR K=X TO X+1:IF ((PEEK(K)-128) AND A)=A THEN LPRINT\"#\";:GOTO 40${nl}30 LPRINT\" \";${nl}40 NEXT K:LPRINT \" \""

rm -f "$tmp" "$lp"
echo "TIPS 1-78: works $W78, keyword-route $K78, dead-harmless $D78, wrong-answer $X78, errors $E78  (of $n78)"
echo "BASIC sections B1-B$((n-n78)): works $((nW-W78)), keyword-route $((nK-K78)), dead-harmless $((nD-D78)), wrong-answer $((nX-X78)), errors $((nE-E78))"
if [ $bad != 0 ]; then echo "TIPS PROBE: $bad MISMATCH(ES) -- behaviour differs from the declared tally"; exit 1; fi
echo "TIPS PROBE OK"
