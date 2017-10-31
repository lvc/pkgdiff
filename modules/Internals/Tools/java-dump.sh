#!/bin/bash

function decompile {
    javap -c -p "$1" \
        | sed '/^Compiled from /d' \
        | sed '/^[ ]*}[ ]*$/d' \
        | sed 's/[ ]\(#[1-9][0-9]*\)[ ,]/ /' \
        | sed 's/[ ]\([0-9]*[:]\)//' \
        | sed 's/[ ][ ]*/ /g' \
        | sed '/Code:$/,/^$/s/^[ ]*\([^ ]\)/    \1/g' \
        | sed '/Code:$/d'
}

function hash_bodies {
    awk '/^[  ]{0,3}[^ ]/{if (x)print x"\n";x="";}{x=(!x)?$0"\n--":x" "$0;}END{print x;}' \
        | sed '/^--[ ]*$/d' \
        | awk "{ if(/^--/) system(\"printf '    '; (echo '\"\$0\"' | shasum --algorithm 256)\"); else print }" \
        | sed 's/[ ][ ]*-$//'
}

function contents_of {
    decompile "$1" | hash_bodies
}

contents_of "$1"
