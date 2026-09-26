#!/bin/sh
# print.sh -- two things the ROM's PRINT does to the screen that a cursor
# move does not (the 2026-09-19 audit, H-4 and H-3):
#   a comma PRINTS blanks to the next 16-column zone (2123-2135 -> 215A):
#     they are in the text stream, they overwrite what was on the screen,
#     and they reach the printer when video is routed to it; from column
#     48 on, a carriage return;
#   a carriage return BLANKS the line it lands on (video driver, 0564-058B)
#     -- the redraw-without-CLS idiom depends on it -- while running off the
#     end of a line is not a carriage return and erases nothing.
# Self-checking: exits 1 on any mismatch.  Run from the repo root:
#   sh programs/tests/print.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
tmp=$(mktemp) || exit 2
lp="$tmp.lp"
fail() { echo "PRINT FAILED: $1"; printf '%s\n' "$2" | sed 's/$/|/'; rm -f "$tmp" "$lp"; exit 1; }
run() { rm -f "$lp"; TRS80_Z80= TRS80_PRINTER="$lp" "$here/basic" "$tmp" 2>&1 </dev/null; }

# the text stream
printf '10 PRINT "NAME","SCORE","LEVEL"\n20 PRINT 1,2,3,4,5\n30 PRINT "A",\n40 PRINT "B"\n' > "$tmp"
out=$(run)
want="NAME            SCORE           LEVEL
 1               2               3               4 
 5 
A               B"
[ "$out" = "$want" ] || fail "commas in the text stream" "$out"

# the blanks overwrite what was on the screen
printf '10 CLEAR 500:CLS:PRINT@0,STRING$(40,"X");:PRINT@0,"A","B";\n20 S$="":FOR I=15360 TO 15360+39:S$=S$+CHR$(PEEK(I)):NEXT\n30 PRINT@128,"[";S$;"]"\n' > "$tmp"
out=$(run | tail -1 | sed "s/.*\[/[/")
[ "$out" = "[A               BXXXXXXXXXXXXXXXXXXXXXXX]" ] || fail "a comma did not blank the stale cells" "$out"

# video routed to the printer: the gap is printed there too.  It is 16
# blanks, not 15: the zone is measured from the video cursor (40A6H), which
# only the video driver moves, and the video driver is not being called
printf '10 POKE 16414,141:POKE 16415,5:PRINT "A","B":POKE 16414,88:POKE 16415,4\n' > "$tmp"
out=$(run); p=$(cat "$lp" 2>/dev/null)
[ "$p" = "A                B" ] || fail "commas routed to the printer" "$p"

# a carriage return blanks the line it lands on (the audit's repro)
printf '10 CLS\n20 PRINT CHR$(28);"LINE A"\n30 PRINT "LONGER TEXT HERE"\n40 PRINT CHR$(28);"LINE A"\n50 PRINT "SHORT";\n60 S$="":FOR I=15424 TO 15424+19:S$=S$+CHR$(PEEK(I)):NEXT:PRINT@192,"[";S$;"]"\n' > "$tmp"
out=$(run | tail -1 | sed "s/.*\[/[/")
[ "$out" = "[SHORT               ]" ] || fail "a carriage return left stale text on the next line" "$out"

# running off the end of a line is NOT a carriage return: row 1 keeps its tail
printf '10 CLS:PRINT@74,"KEEPME";:PRINT@0,STRING$(70,"X");\n20 S$="":FOR I=15424 TO 15424+15:S$=S$+CHR$(PEEK(I)):NEXT:PRINT@192,"[";S$;"]"\n' > "$tmp"
out=$(run | tail -1 | sed "s/.*\[/[/")
[ "$out" = "[XXXXXX    KEEPME]" ] || fail "a line wrap erased the next line" "$out"

# a number is never split across two lines: when the column plus its length
# (sign and digits, not the blank after it) reaches 64 the ROM sends a
# carriage return first (20DD-20E6); a string just wraps.  LPRINT has the
# same rule against 132 columns (20D5-20DB).
printf '10 CLEAR 500:PRINT STRING$(59,"X");1234\n20 PRINT STRING$(60,"X");1234\n30 PRINT STRING$(60,"X");"ABCDEFGH"\n40 FOR I=1001 TO 1012:PRINT I;:NEXT:PRINT\n50 FOR I=1001 TO 1024:LPRINT I;:NEXT:LPRINT\n' > "$tmp"
out=$(run); p=$(cat "$lp" 2>/dev/null)
want="XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
 1234 
XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
 1234 
XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXABCDEFGH
 1001  1002  1003  1004  1005  1006  1007  1008  1009  1010 
 1011  1012 "
[ "$out" = "$want" ] || fail "a number that does not fit goes to the next line" "$out"
want=" 1001  1002  1003  1004  1005  1006  1007  1008  1009  1010  1011  1012  1013  1014  1015  1016  1017  1018  1019  1020  1021  1022 
 1023  1024 "
[ "$p" = "$want" ] || fail "LPRINT: a number that does not fit goes to the next line" "$p"

# ROM 050E-0513: the video driver sends 0AH, 0BH, 0CH and 0DH all to the
# carriage return at 0564H.  CHR$(11) and CHR$(12) were no-ops here (the
# 2026-09-19 audit, L-2); a code below 0AH still is, 08H aside, and so is
# 09H.  Each of the four also blanks the line it lands on, as H-3 has it.
printf '10 PRINT "A";CHR$(10);"B";CHR$(11);"C";CHR$(12);"D";CHR$(13);"E"\n' > "$tmp"
out=$(run)
want="A
B
C
D
E"
[ "$out" = "$want" ] || fail "CHR\$(10) to CHR\$(13) are all carriage returns" "$out"

printf '10 PRINT "A";CHR$(0);CHR$(7);CHR$(9);CHR$(16);CHR$(20);"B"\n' > "$tmp"
out=$(run)
[ "$out" = "AB" ] || fail "the control codes that are ignored still are" "$out"

# ... and each blanks the line it lands on, as a CHR$(13) does (H-3): read
# the second screen row back rather than the text stream, which shows only
# what was printed
printf '10 CLS\n20 PRINT CHR$(28);"LINE A"\n30 PRINT "LONGER TEXT HERE"\n40 PRINT CHR$(28);"LINE A";CHR$(11);"SHORT";\n50 S$="":FOR I=15424 TO 15424+19:S$=S$+CHR$(PEEK(I)):NEXT:PRINT@192,"[";S$;"]"\n' > "$tmp"
out=$(run | tail -1 | sed "s/.*\[/[/")
[ "$out" = "[SHORT               ]" ] || fail "CHR\$(11) blanks the line it lands on" "$out"

# a PRINT that ends in TAB(n) ends WITHOUT a carriage return, like one
# that ends in ; or ,: the TAB path rejoins the loop at 20A0H, past the CR
# call at 209DH (2164H-2166H).  LPRINT is the same routine (the 2026-09-23
# audit, M-3).
printf '10 PRINT "A";TAB(5)\n20 PRINT "B"\n30 PRINT TAB(3)\n40 PRINT "C"\n50 LPRINT "D";TAB(5)\n60 LPRINT "E"\n' > "$tmp"
out=$(run); p=$(cat "$lp" 2>/dev/null)
[ "$out" = "A    B
   C" ] || fail "a trailing TAB printed a carriage return" "$out"
[ "$p" = "D    E" ] || fail "a trailing TAB printed a carriage return on the printer" "$p"

# a bare REM token in the item list is ?SN, as on the ROM, where the item
# evaluator meets it (20B9H -> 2337H); PRINT# already had it (L-10)
printf '10 ON ERROR GOTO 100:N=0\n20 S=1:PRINT REM X\n30 S=2:LPRINT REM X\n40 S=3:PRINT USING "#";REM X\n50 S=4:LPRINT USING "#";REM X\n60 PRINT "SN";N\n70 END\n100 IF ERR/2+1=2 THEN N=N+1 ELSE PRINT "STEP";S;"ERR";ERR/2+1\n110 RESUME NEXT\n' > "$tmp"
out=$(run)
[ "$out" = "SN 4 " ] || fail "a bare REM in a PRINT list must be ?SN" "$out"

# in 32-character mode the column TAB, the comma and POS measure by is the
# CHARACTER column: the ROM recomputes 40A6H after every byte from the
# cursor address, rotated right and masked to 0-31 in that mode
# (032AH-0355H), while PRINT @ stores its byte offset AND 3FH as it is
# (2086H-2089H).  The screen is read back through PEEK, two bytes per
# character (M-4).
printf '10 CLS:PRINT CHR$(23);"ABC";TAB(10);"X";:P=POS(0):PRINT\n20 PRINT "AB","C"\n30 PRINT @70,TAB(10);"Y"\n40 PRINT CHR$(28);PEEK(15380);PEEK(15456);PEEK(15438);P\n' > "$tmp"
out=$(run)
case "$out" in *" 88  67  89  11 "*) ;; *) fail "the 32-character column (TAB, comma, PRINT @ then TAB, POS)" "$out" ;; esac

# the number fit (20DD-20E6): 40A6H plus the number's length (sign and
# digits) against 409DH, a carriage return first when that reaches 64.
# In 32-character mode 40A6H counts characters and 409DH stays 64 -- the
# ROM never updates it -- so the test cannot fire and a number IS split
# at the right edge (trs-80.com ROM bug 1, in every revision; followed,
# ruled 2026-09-25).  Read back through PEEK: 123456 after 30 characters
# has its 1 at byte 62, its 2 at byte 64 (the start of the next row) and
# its 6 at byte 72.
# Until 2026-09-25 the display byte was measured, so that number moved
# to a line of its own.  In 64-character mode " 123" after 60 characters
# is the last that does not fit (60 + 4 = 64) and " 12" the first that does.
printf '10 CLS:PRINT CHR$(23);STRING$(30,"X");123456;\n20 A=PEEK(15422):B=PEEK(15424):C=PEEK(15432)\n30 PRINT CHR$(28);:CLS:PRINT STRING$(60,"X");123;\n40 D=PEEK(15425):CLS:PRINT STRING$(60,"X");12;\n50 E=PEEK(15421):F=PEEK(15424):CLS:PRINT A;B;C;D;E;F\n' > "$tmp"
out=$(run)
case "$out" in *" 49  50  54  49  49  32 "*) ;; *) fail "the number fit is 40A6H against 409DH (64, never updated for 32 characters)" "$out" ;; esac

# ROM 1.3 (the target revision, ruled 2026-09-25): the PRINT loop
# re-examines the code string before every item (207CH), so an @ position
# stands anywhere in the list and more than once, each followed by its
# comma (Farvour's starred 206C-20A3); the revisions before 1.3 took @
# only right after PRINT.  LPRINT shares the loop, so its @ moves the
# video cursor.  TAB's argument is AND 7FH (213AH): TAB(70) from column
# 10 prints 60 blanks, which run on to column 6 of the next line.
printf '10 CLS:PRINT "A";@70,"B";@140,1;2;@200,"C";\n20 PRINT@320,PEEK(15360);PEEK(15430);PEEK(15501);PEEK(15560);PEEK(15431)\n30 CLS:PRINT "ABCDEFGHIJ";TAB(70);"X";:P=POS(0):PRINT@256,PEEK(15430);P\n40 CLS:LPRINT @9,"P";:PRINT POS(0);\n' > "$tmp"
out=$(run); p=$(cat "$lp" 2>/dev/null)
case "$out" in *" 65  66  49  67  32 "*" 88  7 "*" 9 "*) ;; *) fail "PRINT @ anywhere in the list, TAB past 63 (ROM 1.3)" "$out" ;; esac
[ "$p" = "P" ] || fail "LPRINT @ printed its position" "$p"

rm -f "$tmp" "$lp"
echo "PRINT OK"
