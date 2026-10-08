#!/bin/sh
# inputitem.sh -- where INPUT's items end.  The ROM reads a typed line with
# READ's own item reader (21EBH puts a comma in front of the buffer "to
# make READ think" it is in a DATA statement), so the line ends where a
# DATA statement would:
#   * an unquoted ":" ends the item and the data (2869H; RST 10H calls ":"
#     an end of statement, 225B).  What is behind it is never read:
#     ?EXTRA IGNORED, or ?? when variables are still waiting
#   * "AB"CD -- text between the closing quote and the comma -- is ?REDO
#   * a quoted "12" typed for a number is ?REDO
#   * a tab behind the closing quote is skipped like a blank (RST 10H)
#   * an unquoted item keeps its trailing blanks (2869H-287EH)
# Until 2026-09-21 AB:CD came through whole, "AB"CD was AB with the rest of
# the line dropped, and "12" was the number 12.
# Self-checking: exits 1 on any mismatch.  Run from the repo root:
#     sh programs/tests/inputitem.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
tmp=$(mktemp -d) || exit 2
fail() { echo "INPUTITEM FAILED: $1"; printf '%s\n' "$2" | head -30; rm -rf "$tmp"; exit 1; }
run() { ( cd "$tmp" && TRS80_Z80= perl -e 'alarm 20; exec @ARGV' "$here/basic" "$@" 2>&1 ); }

cat > "$tmp/in.bas" <<'BAS'
10 INPUT A$:PRINT "[";A$;"]"
20 INPUT B$,C$:PRINT "[";B$;"][";C$;"]"
30 INPUT D$:PRINT "[";D$;"]"
40 INPUT N:PRINT N
50 INPUT M:PRINT M
60 INPUT E$,F$:PRINT "[";E$;"][";F$;"]"
70 INPUT G$,H$:PRINT "[";G$;"][";H$;"]"
BAS
out=$(printf 'AB:CD,EF\nX:Y\nZ\n"AB"CD\n"OK"\t\n"12"\n12\n5:6\n"A:B","C" ,D\nAB  ,  CD  \n' | run "$tmp/in.bas")
want='? AB:CD,EF
?EXTRA IGNORED
[AB]
? X:Y
?? Z
[X][Z]
? "AB"CD
?REDO
? "OK"
[OK]
? "12"
?REDO
? 12
 12 
? 5:6
?EXTRA IGNORED
 5 
? "A:B","C" ,D
?EXTRA IGNORED
[A:B][C]
? AB  ,  CD  
[AB  ][CD  ]'
[ "$out" = "$want" ] || fail "INPUT" "$out"

# READ's DATA items end the same way: an unquoted item keeps its trailing
# blanks, at a comma and at the ":" that ends the DATA statement
printf '10 DATA ABC  ,  DEF  \n20 DATA G :READ A$,B$,C$:PRINT "[";A$;"][";B$;"][";C$;"]"\n' > "$tmp/d.bas"
out=$(run "$tmp/d.bas")
[ "$out" = "[ABC  ][DEF  ][G ]" ] || fail "DATA" "$out"

# READ finds a DATA statement only where the DATA token begins a statement
# (2296H-22AFH; BL-10): not behind THEN or ELSE.  An unquoted item ends at
# ":" past a quote (2869H), and the search starts again there with no
# quote open, so D" or I" hides the rest of the line, :DATA 9 included.
cat > "$tmp/dt.bas" <<'BAS'
10 ON ERROR GOTO 100
20 IF 1 THEN DATA 5
30 IF 0 THEN 40 ELSE DATA 6
40 DATA AB"C:D",E
50 PRINT "P";: DATA F
60 DATA G"H:I":DATA 9
70 DATA J
80 READ A$,B$,C$,D$:PRINT A$;"/";B$;"/";C$;"/";D$:READ E$
90 END
100 PRINT "E";ERR/2+1;ERL:END
BAS
out=$(run "$tmp/dt.bas")
want='PAB"C/F/G"H/J
E 4  80 '
[ "$out" = "$want" ] || fail "WHERE READ FINDS DATA" "$out"

# The item that fails the test is STORED first (2240-224A, JP 1F33H with
# 225AH pushed; the 2026-09-30 audit, BL-7): ENTER after ?REDO keeps it.
# 2X leaves 2, "Q"R leaves Q, X and a quoted "2" leave 0 for a number,
# 7.5Q into an integer leaves 7; the items behind it keep their values.
cat > "$tmp/st.bas" <<'BAS'
10 A=-1:B=-1:C=-1:A$="-":B$="-":A%=-1
20 INPUT A,B:PRINT A;B
30 A=-1:B=-1:INPUT A$,B$:PRINT A$;"/";B$
40 INPUT A,B,C:PRINT A;B;C
50 A=-1:B=-1:INPUT A,B:PRINT A;B
60 B=-1:INPUT A%,B:PRINT A%;B
BAS
out=$(printf '1,2X\n\nP,"Q"R\n\n1,X\n\n1,"2"\n\n7.5Q,1\n\n' | run "$tmp/st.bas")
want='? 1,2X
?REDO
? 
 1  2 
? P,"Q"R
?REDO
? 
P/Q
? 1,X
?REDO
? 
 1  0 -1 
? 1,"2"
?REDO
? 
 1  0 
? 7.5Q,1
?REDO
? 
 7 -1 '
[ "$out" = "$want" ] || fail "STORED BEFORE ?REDO" "$out"

# The answer is read before the variable list (21DBH), and each target is
# found only when its item is due (21FDH -> 260DH; BL-9): INPUT A,3 asks,
# stores A, then is ?SN -- before any ?? when only 5 was typed -- and ENTER
# alone runs on past a bad list (1F04H skips to the statement's end).
cat > "$tmp/bl.bas" <<'BAS'
10 ON ERROR GOTO 100:N=N+1:A=-1
20 ON N GOTO 30,40,50,60,70
30 INPUT A,3:PRINT "NEXT";A:GOTO 10
40 INPUT A,3:PRINT "NEXT";A:GOTO 10
50 INPUT A,3:PRINT "NEXT";A:GOTO 10
60 INPUT 3,A:PRINT "NEXT";A:GOTO 10
70 INPUT A;B:PRINT "NEXT";A:END
100 PRINT "E";ERR/2+1;ERL;A:RESUME 10
BAS
out=$(printf '5,6\n5\n\n5\n\n' | run "$tmp/bl.bas")
want='? 5,6
E 2  30  5 
? 5
E 2  40  5 
? 
NEXT-1 
? 5
E 2  60 -1 
? 
NEXT-1 '
[ "$out" = "$want" ] || fail "THE ANSWER BEFORE THE LIST" "$out"

rm -rf "$tmp"
echo "INPUTITEM OK"
