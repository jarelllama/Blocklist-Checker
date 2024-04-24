#!/bin/bash

# Generates a markdown report for the given blocklist.

readonly TEMPLATE='data/TEMPLATE.md'
readonly BLOCKLISTS_TO_COMPARE='data/blocklists_to_compare.txt'
readonly URL="$1"

main() {
    # Install AdGuard's Hostlist Compiler
    if ! command -v hostlist-compiler &> /dev/null; then
        npm install -g @adguard/hostlist-compiler
    fi

    # Install AdGuard's Dead Domains Linter
    if ! command -v dead-domains-linter &> /dev/null; then
        npm install -g @adguard/dead-domains-linter
    fi

    execution_time="$(date +%s)"

    # Download blocklist and exit if errored
    curl -L "$URL" -o raw.tmp || exit 1

    # Remove carriage return characters, empty lines, and trailing whitespaces
    sed -i 's/\r//g; /^$/d; s/[[:space:]]*$//' raw.tmp

    # Get blocklist title if present, otherwise, use blocklist URL
    # (use the first occurrence)
    title="$(mawk -F 'Title: ' '/Title:/ {print $2}' raw.tmp | head -n 1)"
    title="${title:-$URL}"

    # Remove Adblock Plus header and comments
    sed -i '/[\[#!]/d' raw.tmp

    # Convert to lowercase
    mawk '{print tolower($0)}' raw.tmp > temp
    mv temp raw.tmp

    # Sort without removing duplicate entries
    sort raw.tmp -o raw.tmp

    process_blocklist

    generate_report
}

process_blocklist() {
    # Count number of raw uncompressed entries
    raw_count="$(wc -l < raw.tmp)"

    create_hostlist_compiler_config

    # Compress and compile to standardized domains format
    # Also removes content modifiers
    compile -c config.json compressed.tmp

    # Count number of compressed entries
    compressed_count="$(wc -l < compressed.tmp)"
    compression_percentage="$(( $(( raw_count - compressed_count )) * 100 / raw_count ))"

    # Check for invalid entries removed by Hostlist Compiler
    compile -i compressed.tmp compiled.tmp
    invalid_entries="$(comm -23 compressed.tmp compiled.tmp)"
    # Note wc -w being used here might cause lines with whitespaces to be
    # miscounted. In theory, no blocklist should have spaces anyway.
    invalid_entries_count="$(wc -w <<< "$invalid_entries")"
    invalid_entries_percentage="$(( invalid_entries_count * 100 / compressed_count ))"

    # Check for domains in Tranco
    if [[ ! -f toplist.tmp ]]; then
        curl -L 'https://tranco-list.eu/top-1m.csv.zip' \
            --retry 2 --retry-all-errors | gunzip - > tranco.tmp
        sed -i 's/^.*,//; s/\r//g' tranco.tmp
        sort tranco.tmp -o tranco.tmp
    fi
    in_tranco="$(comm -12 compressed.tmp tranco.tmp)"
    in_tranco_count="$(wc -w <<< "$in_tranco")"

    # To reduce processing time, 50% of the compressed entries are randomly
    # picked to be processed by the dead check (capped to 10,000 domains).
    # The results of the 50% is a good representation of the actual percentage
    # of dead domains (deviation of +-2%).
    if [[ "$compressed_count" -le 1000 ]]; then
        selection_percentage=100
    else
        selection_percentage=50
    fi
    selection_count="$(( $(wc -l < compressed.tmp) * selection_percentage / 100 ))"
    (( selection_count > 10000 )) && selection_count=10000
    shuf -n "$selection_count" compressed.tmp > selection.tmp

    # Format to Adblock Plus syntax for Dead Domains Linter
    sed -i 's/.*/||&^/' selection.tmp

    # Check for dead domains
    dead-domains-linter -i selection.tmp --export dead_domains.tmp
    # wc -l has trouble providing an accurate count. Seemingly because the Dead
    # Domains Linter does not append a new line at the end.
    dead_count="$(wc -w < dead_domains.tmp)"
    dead_percentage="$(( dead_count * 100 / selection_count ))"

    # Calculate percentage of total usable domains
    usable_percentage="$(( 100 - compression_percentage - dead_percentage \
        - invalid_entries_percentage ))"

    # Find unique and duplicate domains in other blocklists
    duplicates_table="| Unique | Blocklist |\n| ---:|:--- |\n"
    while read -r blocklist; do
        name="$(mawk -F "," '{print $1}' <<< "$blocklist")"
        url="$(mawk -F "," '{print $2}' <<< "$blocklist")"

        if [[ ! -f "${name}_blocklist.tmp" ]]; then
            curl -L "$url" -o "${name}_blocklist.tmp"
            # Remove CRG and convert ABP format to domains
            # Hostlist compiler is not used here as the Compress transformation
            # take a fair bit of time for larger blocklists.
            sed -i 's/\r//g; s/[|\^]//g' "${name}_blocklist.tmp"
            sort -u "${name}_blocklist.tmp" -o "${name}_blocklist.tmp"
        fi

        # wc -l seems to work just fine here
        unique_count="$(comm -23 compressed.tmp "${name}_blocklist.tmp" | wc -l)"
        unique_percentage="$(( unique_count * 100 / compressed_count ))"
        duplicates_table="${duplicates_table}| ${unique_count} (${unique_percentage}%) | ${name} |\n"
    done < "$BLOCKLISTS_TO_COMPARE"

    # Get the top TLDs
    tlds="$(mawk -F '.' '{print $NF}' compressed.tmp | sort | uniq -c \
        | sort -nr | head -n 15)"
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

# Function 'generate_report' creates the markdown report to reply to the issue.
generate_report() {
    # Escape new line characters and slashes
    # -z learnt from :https://linuxhint.com/newline_replace_sed/
    invalid_entries="$(sed -z 's/\n/\\n/g; s/\//\\\//g' <<< "$invalid_entries")"
    in_tranco="$(sed -z 's/\n/\\n/g; s/\//\\\//g' <<< "$in_tranco")"
    tlds="$(sed -z 's/\n/\\n/g; s/\//\\\//g' <<< "$tlds")"
    # Escape slashes and '&'
    title="$(sed 's/[/&]/\\&/g' <<< "$title")"

    replace TITLE "$title"
    replace URL "${URL//\//\\/}"  # Escape slashes
    replace RAW_COUNT "$raw_count"
    replace COMPRESSED_COUNT "$compressed_count"
    replace COMPRESSION_PERCENTAGE "$compression_percentage"
    replace DEAD_PERCENTAGE "$dead_percentage"
    replace INVALID_ENTRIES_COUNT "$invalid_entries_count"
    replace INVALID_ENTRIES_PERCENTAGE "$invalid_entries_percentage"
    replace INVALID_ENTRIES "$invalid_entries"
    replace USABLE_PERCENTAGE "$usable_percentage"
    replace IN_TRANCO_COUNT "$in_tranco_count"
    replace IN_TRANCO "$in_tranco"
    replace DUPLICATES_TABLE "$duplicates_table"
    replace TLDS "$tlds"
    replace PROCESSING_TIME "$(( $(date +%s) - execution_time ))"
    replace GENERATION_TIME "$(date -u)"

    # Remove ending new line for entries
    # Apparently the arguments cannot be combined into -iz
    # shellcheck disable=SC2016
    sed -i -z 's/\n```\n/```\n/g' "$TEMPLATE"
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
    "transformations": ["RemoveComments", "Compress", "RemoveModifiers"]
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
