10 REM OUT 255,v DRIVES THE 32/64-COLUMN LATCH BIT (built 2026-09-13): the hardware switch, not the ROM's 403DH print flag
20 REM self-checking batch fixture: ./basic programs/tests/out255.bas exits 1 on any mismatch
30 DIM Z(1):F=0
40 OUT 255,8:IF INP(255)<>63 THEN PRINT "FAIL OUT 255,8 selects 32 columns";INP(255):F=1
50 OUT 255,0:IF INP(255)<>127 THEN PRINT "FAIL OUT 255,0 returns to 64";INP(255):F=1
60 OUT 255,15:IF INP(255)<>63 THEN PRINT "FAIL bit 3 among the cassette bits";INP(255):F=1
70 OUT 255,7:IF INP(255)<>127 THEN PRINT "FAIL bits 0-2 alone leave 64 columns";INP(255):F=1
80 OUT 255,8:CLS:IF INP(255)<>127 THEN PRINT "FAIL CLS restores 64 after OUT";INP(255):F=1
90 OUT 254,8:OUT 0,8:IF INP(255)<>127 THEN PRINT "FAIL other ports are open bus";INP(255):F=1
100 FOR I=1 TO 50:OUT 255,8:OUT 255,0:NEXT:IF INP(255)<>127 THEN PRINT "FAIL a flashing loop ends at 64";INP(255):F=1
110 OUT 255,8.9:IF INP(255)<>63 THEN PRINT "FAIL the value truncates";INP(255):F=1
120 REM the ROM's print flag (403DH) is untouched by OUT: text still lands on consecutive bytes
130 CLS:OUT 255,8:PRINT@0,"ABCD";:IF PEEK(15360)<>65 OR PEEK(15361)<>66 THEN PRINT "FAIL OUT alone keeps the 1-byte print step";PEEK(15361):F=1
140 REM CHR$(23) sets both: even bytes, step 2; OUT 255,0 then clears the latch but not the flag
150 CLS:PRINT CHR$(23);:PRINT@0,"AB";:IF PEEK(15360)<>65 OR PEEK(15362)<>66 THEN PRINT "FAIL CHR$(23) steps by 2";PEEK(15362):F=1
160 IF INP(255)<>63 THEN PRINT "FAIL CHR$(23) sets the latch";INP(255):F=1
170 OUT 255,0:PRINT@64,"CD";:IF INP(255)<>127 OR PEEK(15424)<>67 OR PEEK(15426)<>68 THEN PRINT "FAIL OUT 255,0 clears the latch, keeps the step":F=1
180 CLS:PRINT@0,"EF";:IF PEEK(15361)<>70 THEN PRINT "FAIL CLS restores the 1-byte step";PEEK(15361):F=1
182 REM the flag byte itself, 16445 (403DH): CHR$(23) sets bit 3, CLS clears it, POKE sets the step without the latch
184 CLS:IF PEEK(16445)<>0 THEN PRINT "FAIL 16445 reads 0 after CLS";PEEK(16445):F=1
185 PRINT CHR$(23);:IF PEEK(16445)<>8 THEN PRINT "FAIL 16445 reads 8 after CHR$(23)";PEEK(16445):F=1
186 CLS:POKE 16445,8:PRINT@0,"GH";:IF PEEK(15362)<>72 OR INP(255)<>127 THEN PRINT "FAIL POKE 16445,8 steps by 2 without the latch":F=1
187 POKE 16445,0:PRINT@64,"IJ";:IF PEEK(15425)<>74 THEN PRINT "FAIL POKE 16445,0 restores the 1-byte step";PEEK(15425):F=1
188 OUT 255,8:POKE 16445,8:PRINT@128,"KL";:IF INP(255)<>63 OR PEEK(15490)<>76 THEN PRINT "FAIL Barden's recipe, OUT 255,8 with POKE 16445,8":F=1
190 OUT 255,0:CLS
200 IF F THEN PRINT "OUT 255 FIXTURE FAILED":Z(9)=0
210 PRINT "OUT 255 FIXTURE OK"
