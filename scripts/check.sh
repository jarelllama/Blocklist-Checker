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
    curl -L --retry 2 --retry-all-errors \
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

    # Find unique and duplicate domains in other blocklists
    printf "| Duplicates | Blocklist |\n| ---:| --- |\n" > duplicate_table.tmp
    while read -r blocklist; do
        name="$(mawk -F "URL: " '{print $1}' <<< "$blocklist")"
        url="$(mawk -F "URL: " '{print $2}' <<< "$blocklist")"

        curl -L "$url" -o external_blocklist.tmp
        compile -i external_blocklist.tmp -o external_blocklist.tmp

        unique_count="$(comm -23 compiled.tmp external_blocklist.tmp | wc -w)"
        unique_percentage="$(( unique_count * 100 / compiled_entries_count ))"
        duplicate_count="$(comm -12 compiled.tmp external_blocklist.tmp | wc -w)"
        printf "| %s | %s |\n" "$duplicate_count" "$name" >> duplicate_table.tmp
    done < "$BLOCKLISTS_TO_COMPARE"
}

# Function 'replace' updates the markdown template with values from the results.
# Input:
#   $1: keyword to replace
#   $2: replacement
replace() {
    sed -i "0,/${1}/s/${1}/${2}/" "$TEMPLATE"
}

# Function 'generate_results' creates the markdown results to reply to the
# issue with.
generate_results() {
    replace TITLE "$title"
    replace URL "$URL"
    replace ENTRIES_REMOVED_COUNT "$entries_removed_count"
    replace ENTRIES_REMOVED_PERCENTAGE "$entries_removed_percentage"
    replace ENTRIES_REMOVED "$entries_removed"
    replace COMPILED_ENTRIES_COUNT "$compiled_entries_count"
    replace ENTRIES_COUNT "$entries_count"
    replace IN_TRANCO_COUNT "$in_tranco_count"
    replace IN_TRANCO "$in_tranco"
    replace DEAD_COUNT "$dead_count"
    replace DEAD_PERCENTAGE "$dead_percentage"
    replace UNIQUE_COUNT "$unique_count"
    replace UNIQUE_PERCENTAGE "$unique_percentage"
    replace DUPLICATE_TABLE "$(<duplicate_table.tmp)"
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