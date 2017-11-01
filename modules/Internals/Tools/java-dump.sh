#!/bin/bash

function decompile {
    # Decompile class and include private members. In preparation for the
    # hashing below, strip references on the form #[0-9]+.
    javap -c -p "$1" \
        | sed '/^Compiled from /d' \
        | sed '/^[ ]*}[ ]*$/d' \
        | sed 's/[ ]\(#[1-9][0-9]*\)[ ,]/ /' \
        | sed 's/[ ]\([0-9]*[:]\)//' \
        | sed 's/[ ][ ]*/ /g' \
        | sed '/Code:$/,/^$/s/^[ ]*\([^ ]\)/    \1/g' \
        | sed '/Code:$/d' \
        | sed 's/ *{$//'
}

function hash_bodies {
    # Generate hashes of the instructions making up the method bodies; Yields
    # more concise summaries.
    awk '/^[  ]{0,3}[^ ]/{if (x)print x"\n";x="";}{x=(!x)?$0"\n--":x" "$0;}END{print x;}' \
        | sed '/^--[ ]*$/d' \
        | awk "{ if(/^--/) system(\"printf '    '; (echo '\"\$0\"' | shasum --algorithm 256)\"); else print }" \
        | sed 's/[ ][ ]*-$//'
}

if [[ "$1" == "-s" ]]; then
    shift 1
    decompile "$1" | hash_bodies
else
    javap -c -s -p -verbose "$1"
fi
