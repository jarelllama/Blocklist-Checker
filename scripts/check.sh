#!/bin/bash

readonly TEMPLATE='data/TEMPLATE.md'
readonly URL="$1"

main() {
    # Install AdGuard's Hostlist Compiler
    if ! command -v hostlist-compiler &> /dev/null; then
        npm install -g @adguard/hostlist-compiler > /dev/null
    fi

    # Install AdGuard's Dead Domains Linter
    if ! command -v dead-domains-linter &> /dev/null; then
        npm install -g @adguard/dead-domains-linter > /dev/null
    fi

    # Download blocklist
    curl -L "$URL" -o blocklist.tmp

    # Get blocklist title if present, otherwise, use blocklist URL
    title="$(mawk -F ': ' '/Title:/ {print $2}' blocklist.tmp)"
    [[ -z "$title" ]] && title="$URL"

    process_blocklist

    generate_results
}

process_blocklist() {
    create_hostlist_compiler_config

    # Remove comments and compile to standardized domains format
    compile -c config.json blocklist.tmp

    # Count number of entries
    entries_count="$(wc -l < blocklist.tmp)"

    # Checked for entries removed by Hostlist Compiler
    compile -i blocklist.tmp compiled.tmp
    entries_removed="$(grep -vxFf compiled.tmp blocklist.tmp)"
    entries_removed_count="$(wc -w <<< "$entries_removed")"
    entries_removed_percentage="$(( entries_removed_count * 100 / entries_count ))"
    compiled_entries_count="$(wc -l < compiled.tmp)"

    # Check for domains in Tranco
    curl -sSL --retry 2 --retry-all-errors \
        'https://tranco-list.eu/top-1m.csv.zip' | gunzip - > tranco.tmp
    sed -i 's/^.*,//' tranco.tmp
    in_tranco="$(grep -xFf blocklist.tmp tranco.tmp)"
    in_tranco_count="$(wc -w <<< "$in_tranco")"

    # Format to Adblock Plus syntax for Dead Domains Linter
    sed 's/.*/||&^/' blocklist.tmp > temp
    # Check for dead domains
    printf "\n"
    dead-domains-linter -i temp --export dead.tmp
    # wc -l has trouble providing an accurate count. Seemingly because the Dead
    # Domains Linter does not append a new line at the end.
    dead_count="$(wc -w < dead.tmp)"
    dead_percentage="$(( dead_count * 100 / entries_count ))"

    # Check for domain coverage in other blocklists
    blocklists=(
        https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/domains/tif.txt
        https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/domains/ultimate.txt
    )

    #for blocklist in "${blocklists[@]}"; do
    #    curl -sSL "$blocklist" -o external_blocklist.tmp
    #    compile -i external_blocklist.tmp -o external_blocklist.tmp
    #    comm -23 compiled.tmp external_blocklist.tmp
    #done
}

# Function 'replace' updates the markdown template with values from the results.
# Input:
#   $1: keyword to replace
#   $2: replacement
replace() {
    sed -i "s/${1}/${2}/" "$TEMPLATE"
}

# Function 'generate_results' creates the markdown results to reply to the
# issue with.
generate_results() {
    replace TITLE "$title"
    replace URL "$URL"
    replace ENTRIES_COUNT "$entries_count"
    replace ENTRIES_REMOVED_COUNT "$entries_removed_count"
    replace ENTRIES_REMOVED_PERCENTAGE "$entries_removed_percentage"
    replace ENTIRES_REMOVED "$entries_removed"
    replace COMPILED_ENTRIES_COUNT "$compiled_entries_count"
    replace IN_TRANCO "$in_tranco"
    replace IN_TRANCO_COUNT "$in_tranco_count"
    replace DEAD_COUNT "$dead_count"
    replace DEAD_PERCENTAGE "$dead_percentage"
}

# Function 'create_hostlist_compiler_config' creates the temporary
# configuration file for the Hostlist Compiler.
create_hostlist_compiler_config() {
    cat << EOF > config.json
{
"name": "Blocklist",
"sources": [
    {
    "source": "blocklist.tmp",
    "transformations": ["RemoveComments", "Compress"]
    }
]
}
EOF
}

# Function 'compile' compiles the blocklist using AdGuard's Hostlist Compiler
# and outputs the compiled blocklist without comments.
# Input:
#   $1: argument to pass to Hostlist Compiler
#   $2: argument to pass to Hostlist Compiler
#   $3: name of file to output
# Output:
#   file passed in $3
compile() {
    printf "\n"
    hostlist-compiler "$1" "$2" -o temp
    mawk '!/^!/ {gsub(/\||\^/, "", $0); print $0}' temp > "$3"
}

main "$1"