#!/bin/bash

# Generates a markdown report for the given blocklist.

readonly URL="$1"
readonly TEMPLATE='data/TEMPLATE.md'
readonly BLOCKLISTS_TO_COMPARE='data/blocklists_to_compare.txt'

main() {
    # Install AdGuard's Hostlist Compiler
    if ! command -v hostlist-compiler &> /dev/null; then
        npm install -g @adguard/hostlist-compiler
    fi

    # Install AdGuard's Dead Domains Linter
    if ! command -v dead-domains-linter &> /dev/null; then
        npm install -g @adguard/dead-domains-linter
    fi

    # Download Tranco
    curl -L 'https://tranco-list.eu/top-1m.csv.zip' \
        --retry 2 --retry-all-errors | gunzip - > tranco.tmp
    sed -i 's/^.*,//; s/\r//g' tranco.tmp
    sort -u tranco.tmp -o tranco.tmp

    # Download blocklists for comparison
    while read -r blocklist; do
        # Remove carriage return characters and convert ABP to Domains
        # Hostlist compiler is not used here as the Compress transformation
        # take a fair bit of time for larger blocklists.
        curl -L --retry 2 --retry-all-errors \
            "$(mawk -F ',' '{print $2}' <<< "$blocklist")" \
            | sed 's/\r//g; s/[|\^]//g' | sort -u -o \
            "$(mawk -F ',' '{print $1}' <<< "$blocklist")_blocklist.tmp"
    done <<< "$BLOCKLISTS_TO_COMPARE"

    execution_time="$(date +%s)"

    # Download blocklist and exit if errored
    curl -L "$URL" -o raw.tmp || exit 1

    # Remove carriage return characters, empty lines, and trailing whitespaces
    sed -i 's/\r//g; /^$/d; s/[[:space:]]*$//' raw.tmp

    # Get blocklist title if present. Else, use blocklist URL
    # (use the first occurrence as AdGuard's DNS filter has multiple titles)
    blocklist_title="$(grep -Po -m 1 "Title: \K.*$" raw.tmp || echo "$URL")"

    # Remove Adblock Plus header, comments, convert to lowercase, and sort
    # without removing duplicate entries
    mawk '!/[\[#!]/ {print tolower($0)}' raw.tmp | sort -o temp
    mv temp raw.tmp

    # Count number of raw uncompressed entries
    raw_entries_count="$(wc -l < raw.tmp)"
    readonly raw_entries_count

    # Compress, remove duplicates, remove content modifiers and compile to
    # Domains format
    create_hostlist_compiler_config
    compile -c config.json compressed.tmp

    # Count number of compressed entries
    compressed_entries_count="$(wc -l < compressed.tmp)"
    compression_percentage="$(( $(( raw_entries_count - compressed_entries_count )) * 100 / raw_entries_count ))"
    readonly compressed_entries_count compression_percentage

    # Set percentage_to_use and entries_to_use for dead domains check.
    # If there are less than 1000 entries, use 100% of the entries. Else,
    # use 50% to save processing time.
    if [[ "$compressed_entries_count" -le 1000 ]]; then
        percentage_to_use=100
    else
        percentage_to_use=50
    fi

    entries_to_use="$(( compressed_entries_count * percentage_to_use / 100 ))"
    # Cap to 10,000 entries
    (( entries_to_use > 10000 )) && entries_to_use=10000

    # Get random entries and check for dead domains using Dead Domains Linter
    shuf -n "$entries_to_use" compressed.tmp | sed 's/.*/||&^/' | sort -o temp
    dead-domains-linter -i temp --export dead_domains.tmp

    # Count number of dead domains
    dead_entries_count="$(wc -l < dead_domains.tmp)"
    dead_entries_percentage="$(( dead_entries_count * 100 / entries_to_use ))"
    readonly dead_entries_count dead_entries_percentage

    # Check for invalid entries removed by Hostlist Compiler
    compile -i compressed.tmp temp
    invalid_entries="$(comm -23 compressed.tmp temp)"
    if [[ -z "$invalid_entries" ]]; then
        invalid_entries_count=0
    else
        invalid_entries_count="$(wc -l <<< "$invalid_entries")"
    fi
    invalid_entries_percentage="$(( invalid_entries_count * 100 / compressed_entries_count ))"
    readonly invalid_entries invalid_entries_count invalid_entries_percentage

    # Check for domains in Tranco
    entries_in_tranco="$(comm -12 compressed.tmp tranco.tmp)"
    if [[ -z "$entries_in_tranco" ]]; then
        entries_in_tranco_count=0
    else
        entries_in_tranco_count="$(wc -l <<< "$entries_in_tranco")"
    fi
    readonly entries_in_tranco entries_in_tranco_count

    # Calculate percentage of total usable compressed domains
    # The '100' here is 100% of the compressed blocklist
    usable_entries_percentage="$(( 100 - dead_entries_percentage - invalid_entries_percentage ))"
    readonly usable_entries_percentage

    # Find unique and duplicate domains in other blocklists
    comparison_table="| Unique | Blocklist |\n| ---:|:--- |\n"
    for blocklist in *_blocklist.tmp; do
        blocklist_name="${blocklist%_blocklist.tmp}"
        unique_entries_count="$(comm -23 compressed.tmp "${blocklist_name}_blocklist.tmp" | wc -l)"
        unique_entries_percentage="$(( unique_entries_count * 100 / compressed_entries_count ))"
        comparison_table="${comparison_table}| ${unique_entries_count} **(${unique_entries_percentage}%)** | ${blocklist_name} |\n"
    done

    # Get the top TLDs
    tlds="$(mawk -F '.' '{print $NF}' compressed.tmp | sort | uniq -c \
        | sort -nr | head -n 15)"

    generate_report
}

# Update the markdown template with values from the results. Note that only the
# first occurrence in the file is replaced.
# Input:
#   $1: keyword to replace
#   $2: replacement
replace() {
    line="$2"

    # Check if the replacement is a single line or multiple
    if [[ "$(wc -l <<< "$line")" -gt 1 ]]; then
        # Limit to 1000 entries to avoid 'Argument list too long' error
        # Escape new line characters and slashes
        # -z learnt from :https://linuxhint.com/newline_replace_sed/
        line="$(head -n 1000 <<< "$line" | sed -z 's/\n/\\n/g; s/[/]/\\&/g')"
    fi

    printf "%s\n" "$line"  # Print replacements for debugging
    sed -i "0,/${1}/s/${1}/${line}/" "$TEMPLATE"
}

# Create the markdown report to reply to the issue.
generate_report() {
    blocklist_title="${blocklist_title//&/\\&}"  # Escape '&'
    replace TITLE "${blocklist_title//[\/]/\\/}"  # Escape slashes
    replace URL "${URL//[\/]/\\/}"  # Escape slashes
    replace RAW_ENTRIES_COUNT "$raw_entries_count"
    replace COMPRESSED_ENTRIES_COUNT "$compressed_entries_count"
    replace COMPRESSION_PERCENTAGE "$compression_percentage"
    replace DEAD_ENTRIES_PERCENTAGE "$dead_entries_percentage"
    replace INVALID_ENTRIES_COUNT "$invalid_entries_count"
    replace INVALID_ENTRIES_PERCENTAGE "$invalid_entries_percentage"
    replace INVALID_ENTRIES "$invalid_entries"
    replace USABLE_ENTRIES_PERCENTAGE "$usable_entries_percentage"
    replace ENTRIES_IN_TRANCO_COUNT "$entries_in_tranco_count"
    replace ENTRIES_IN_TRANCO "$entries_in_tranco"
    replace COMPARISON_TABLE "$comparison_table"
    replace TLDS "$tlds"
    replace PROCESSING_TIME "$(( $(date +%s) - execution_time ))"
    replace GENERATION_TIME "$(date -u)"

    # Disabled because it causes more problems than it solves
    # Remove ending new line for entries
    # Apparently the arguments cannot be combined into -iz
    #sed -i -z 's/\n```\n/```\n/g' "$TEMPLATE"
}

# Create the temporary configuration file for the Hostlist Compiler.
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

# Compile the blocklist using AdGuard's Hostlist Compiler and output the
# compiled blocklist in domains format without comments.
# Input:
#   $1: argument to pass to Hostlist Compiler
#   $2: argument to pass to Hostlist Compiler
#   $3: name of file to output
# Output:
#   file passed in $3
compile() {
    hostlist-compiler "$1" "$2" -o temp
    mawk '/^[|]/ {gsub(/[|^]/, ""); print $0}' temp | sort -u -o "$3"
}

# Entry point

set -e

main
