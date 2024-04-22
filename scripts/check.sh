#!/bin/bash

readonly TEMPLATE='data/TEMPLATE.md'

main() {
    # Download blocklist
    curl -L "$1" -o blocklist.tmp
    printf "\n"

    process

    #print_stats

    generate_results
}

process() {
    # Install AdGuard's Hostlist Compiler
    if ! command -v hostlist-compiler &> /dev/null; then
        npm install -g @adguard/hostlist-compiler > /dev/null
    fi

    # Install AdGuard's Dead Domains Linter
    if ! command -v dead-domains-linter &> /dev/null; then
        npm install -g @adguard/dead-domains-linter > /dev/null
    fi

    # Create Hostlist Compiler config
    create_config

    # Remove comments and compile to standardized domains format
    compile -c config.json blocklist.tmp

    # Count number of entries
    entries_count="$(wc -l < blocklist.tmp)"

    # Checked for entries removed by Hostlist Compiler
    compile -i blocklist.tmp compiled.tmp
    lines_removed="$(grep -vxFf compiled.tmp blocklist.tmp)"
    entries_after="$(wc -l < compiled.tmp)"

    # Check for domains in Tranco
    curl -sSL 'https://tranco-list.eu/top-1m.csv.zip' | gunzip - > tranco.tmp
    sed -i 's/^.*,//' tranco.tmp
    in_tranco="$(grep -xFf blocklist.tmp tranco.tmp)"

    # Check for dead domains
    sed 's/.*/||&^/' blocklist.tmp > temp
    printf "\n"
    # DISABLE FOR NOW
    #dead-domains-linter -i temp --export dead.tmp
    # wc -l shows 0 dead when there 1 dead domain. Seemingly because the Dead
    # Domains Linter does not append a new line at the end.
    #dead_count="$(wc -w < dead.tmp)"

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

generate_results() {
    replace 'ENTRIES_COUNT' "$entries_count"
}

replace() {
    sed -i "s/${1}/{$2}/g" "$TEMPLATE"
}

print_stats() {
    printf "\n* Number of raw entries: %s\n\n" "$entries_before"

    printf "* Lines removed by Hostlist Compiler (%s):\n---\n%s\n---\n\n" \
        "$(wc -w <<< "$lines_removed")" "$lines_removed"

    printf "* Number of entries after compiling: %s (%s%% removed)\n\n" \
        "$entries_after" "$(( ( entries_before - entries_after )*100/entries_before ))"

    printf "* Domains found in Tranco (%s):\n---\n%s\n---\n\n" \
        "$(wc -w <<< "$in_tranco")" "$in_tranco"

    printf "* Number of dead domains: %s (%s%%)\n\n" "$dead_count" \
        "$(( dead_count*100/entries_before ))"
}

compile() {
    printf "\n"
    hostlist-compiler "$1" "$2" -o temp
    mawk '!/^!/ {gsub(/\||\^/, "", $0); print $0}' temp > "$3"
}

create_config() {
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

main "$1"