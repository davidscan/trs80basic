#!/bin/sh
# Stand-in for curl in tests: set TRS80_OLLAMA_CURL="sh programs/tests/ollama_stub.sh"
# and the interpreter appends the JSON request body file as the last argument.
# Prints a canned /api/chat (stream:false) response whose content reports how
# many "role" fields the request carried -- so a growing conversation history
# is observable.  First arg --fail simulates a transport failure.
if [ "$1" = "--fail" ]; then
    exit 7
fi
N=`grep -o '"role"' "$1" | wc -l | tr -d ' '`
# Request options are echoed so a test can see they were sent: T=think
# field value or "-", K=keep_alive or "-".  With a "format" schema present
# the content is a JSON object whose token is the LAST enum value (so a
# test can tell the schema reached us) -- the shape Ollama returns for
# structured output.
T=`grep -o '"think":[a-z]*' "$1" | sed 's/.*://'`; [ -n "$T" ] || T=-
K=`grep -o '"keep_alive":"[^"]*"' "$1" | sed 's/.*:"//; s/"$//'`; [ -n "$K" ] || K=-
if grep -q '"format"' "$1"; then
    TOK=`grep -o '"enum":\[[^]]*\]' "$1" | sed 's/.*,"//; s/.*\["//; s/"\]$//'`
    printf '%s\n' '{"model":"stub","message":{"role":"assistant","content":"{\"token\":\"'"$TOK"'\",\"reply\":\"Msgs='"$N"' T='"$T"' K='"$K"'\\nsecond line\"}"},"done":true}'
else
    printf '%s\n' '{"model":"stub","message":{"role":"assistant","content":"Msgs='"$N"' T='"$T"' K='"$K"', hello\nline \"two\"\n10,20,THREE"},"done":true}'
fi
