#!/bin/bash

readonly TEMPLATE='data/TEMPLATE.md'
readonly BLOCKLISTS_TO_COMPARE='data/blocklists_to_compare.txt'
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

    execution_time="$(date +%s)"

    # Download blocklist
    curl -L "$URL" -o raw.tmp
    sort raw.tmp -o raw.tmp

    # Get blocklist title if present, otherwise, use blocklist URL
    title="$(mawk -F ': ' '/Title:/ {print $2}' raw.tmp)"
    [[ -z "$title" ]] && title="$URL"

    # Remove AdBlock Plus header and comments
    sed -i '/[\[#!]/d' raw.tmp

    process_blocklist

    generate_results
}

process_blocklist() {
    # Count number of raw uncompressed entries
    raw_count="$(wc -l < raw.tmp)"

    create_hostlist_compiler_config

    # Compress and compile to standardized domains format
    compile -c config.json compressed.tmp

    # Count number of compressed entries
    compressed_count="$(wc -l < compressed.tmp)"

    # Check for invalid entries removed by Hostlist Compiler (uses compressed)
    compile -i compressed.tmp compiled.tmp
    invalid_entries="$(comm -23 compressed.tmp compiled.tmp)"
    # Note wc -w being used here might cause lines with whitespaces to be
    # miscounted. In theory, no blocklist should have spaces anyway.
    invalid_entries_count="$(wc -w <<< "$invalid_entries")"
    invalid_entries_percentage="$(( invalid_entries_count * 100 / compressed_count ))"

    # Check for domains in Tranco (uses raw)
    curl -L --retry 2 --retry-all-errors 'https://tranco-list.eu/top-1m.csv.zip' \
        | gunzip - > tranco.tmp
    sed -i 's/^.*,//' tranco.tmp
    sort tranco.tmp -o tranco.tmp
    in_tranco="$(comm -12 raw.tmp tranco.tmp)"
    in_tranco_count="$(wc -w <<< "$in_tranco")"

    # To reduce processing time, 60% of the domains are randomly picked to be
    # processed by the dead check. (uses compressed)
    sixty_percent="$(( $(wc -l < compressed.tmp) * 60 / 100 ))"
    shuf -n "$sixty_percent" compressed.tmp > sixty_percent.tmp

    # Format to Adblock Plus syntax for Dead Domains Linter
    sed -i 's/.*/||&^/' sixty_percent.tmp

    # Check for dead domains
    dead-domains-linter -i sixty_percent.tmp --export dead.tmp
    # wc -l has trouble providing an accurate count. Seemingly because the Dead
    # Domains Linter does not append a new line at the end.
    dead_count="$(wc -w < dead.tmp)"
    # Note that the dead percentage is calculated from the 60% of compressed
    # entries selected for the dead check.
    dead_percentage="$(( dead_count * 100 / sixty_percent ))"

    # Find unique and duplicate domains in other blocklists (uses raw)
    table="| Unique | Blocklist |\n| ---:|:--- |\n"
    while read -r blocklist; do
        name="$(mawk -F "," '{print $1}' <<< "$blocklist")"
        url="$(mawk -F "," '{print $2}' <<< "$blocklist")"

        # Note that currently only blocklists in domains format are supported
        # for comparing (ABP requires also converting raw.tmp to ABP).
        curl -L "$url" -o blocklist.tmp
        # Remove comments
        sed -i '/[\[#!]/d' blocklist.tmp
        sort -u blocklist.tmp -o blocklist.tmp

        # wc -l seems to work just fine here
        unique_count="$(comm -23 raw.tmp blocklist.tmp | wc -l)"
        unique_percentage="$(( unique_count * 100 / raw_count ))"
        table="${table}| ${unique_count} (${unique_percentage}%) | ${name} |\n"
    done < "$BLOCKLISTS_TO_COMPARE"
}

# Function 'replace' updates the markdown template with values from the
# results. Note that only the first occurrence in the file is replaced.
# Input:
#   $1: keyword to replace
#   $2: replacement
replace() {
    printf "%s\n" "$2"  # Print replacements for debugging
    sed -i "0,/${1}/s/${1}/${2}/" "$TEMPLATE"
}

# Function 'generate_results' creates the markdown results to reply to the
# issue with.
generate_results() {
    replace TITLE "${title//\//\\/}"  # Escape slashes
    replace URL "${URL//\//\\/}"  # Escape slashes
    replace RAW_COUNT "$raw_count"
    replace COMPRESSED_COUNT "$compressed_count"
    replace INVALID_ENTRIES_COUNT "$invalid_entries_count"
    replace INVALID_ENTRIES_PERCENTAGE "$invalid_entries_percentage"
    replace INVALID_ENTRIES "${invalid_entries//$'\n'/\\n}"  # Escape new line
    replace IN_TRANCO_COUNT "$in_tranco_count"
    replace IN_TRANCO "${in_tranco//$'\n'/\\n}"  # Escape new line
    replace DEAD_PERCENTAGE "$dead_percentage"
    replace DUPLICATE_TABLE "$table"
    replace PROCESSING_TIME "$(( $(date +%s) - execution_time ))"
    replace GENERATION_TIME "$(date -u)"
}

# Function 'create_hostlist_compiler_config' creates the temporary
# configuration file for the Hostlist Compiler.
create_hostlist_compiler_config() {
    cat << EOF > config.json
{
"name": "Blocklist",
"sources": [
    {
    "source": "raw.tmp",
    "transformations": ["RemoveComments", "Compress"]
    }
]
}
EOF
}

# Function 'compile' compiles the blocklist using AdGuard's Hostlist Compiler
# and outputs the compiled blocklist in domains format without comments.
# Input:
#   $1: argument to pass to Hostlist Compiler
#   $2: argument to pass to Hostlist Compiler
#   $3: name of file to output
# Output:
#   file passed in $3
compile() {
    hostlist-compiler "$1" "$2" -o temp
    mawk '!/^!/ {gsub(/\||\^/, "", $0); print $0}' temp | sort -o "$3"
}

main "$1"
