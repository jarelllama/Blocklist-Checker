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

    # Download Hagezi's dead domains file to use as a "cache"
    if [[ ! -f dead_cache.tmp ]]; then
        curl -LZ "https://github.com/hagezi/dns-blocklists/raw/main/share/dead.list-a[a-f]" \
            | sort -u -o dead_cache.tmp
    fi

    # Download Tranco
    if [[ ! -f tranco.tmp ]]; then
        curl -L 'https://tranco-list.eu/top-1m.csv.zip' \
            --retry 2 --retry-all-errors | gunzip - > tranco.tmp
        sed -i 's/^.*,//; s/\r//g' tranco.tmp
        sort tranco.tmp -o tranco.tmp
    fi

    # Download blocklists for comparison
    while read -r blocklist; do
        name="$(mawk -F "," '{print $1}' <<< "$blocklist")"
        url="$(mawk -F "," '{print $2}' <<< "$blocklist")"

        if [[ ! -f "${name}_blocklist.tmp" ]]; then
            curl -L --retry 2 --retry-all-errors "$url" \
                -o "${name}_blocklist.tmp"
            # Remove carriage return characters and convert ABP to Domains
            # Hostlist compiler is not used here as the Compress transformation
            # take a fair bit of time for larger blocklists.
            sed -i 's/\r//g; s/[|\^]//g' "${name}_blocklist.tmp"
            sort -u "${name}_blocklist.tmp" -o "${name}_blocklist.tmp"
        fi
    done <<< "$(sort $BLOCKLISTS_TO_COMPARE)"

    execution_time="$(date +%s)"

    # Download blocklist and exit if errored
    curl -L "$URL" -o raw.tmp || exit 1

    # Remove carriage return characters, empty lines, and trailing whitespaces
    # Copied over from the Scam Blocklist, that's why it's on its own line
    sed -i 's/\r//g; /^$/d; s/[[:space:]]*$//' raw.tmp

    # Get blocklist title if present, otherwise, use blocklist URL
    # (use the first occurrence- AdGuard's DNS filter has multiple titles)
    title="$(mawk -F 'Title: ' '/Title:/ {print $2}' raw.tmp | head -n 1)"
    title="${title:-$URL}"

    # Remove Adblock Plus header, comments, convert to lowercase, and sort
    # without removing duplicate entries
    sed '/[\[#!]/d' raw.tmp | mawk '{print tolower($0)}' | sort -o temp
    mv temp raw.tmp

    process_blocklist

    generate_report
}

process_blocklist() {
    # Count number of raw uncompressed entries
    raw_count="$(wc -l < raw.tmp)"

    # Compress and compile to standardized Domains format
    # (removes content modifiers)
    create_hostlist_compiler_config
    compile -c config.json compressed.tmp

    # Count number of compressed entries
    compressed_count="$(wc -l < compressed.tmp)"
    compression_percentage="$(( $(( raw_count - compressed_count )) * 100 / raw_count ))"

    # To reduce processing time, 50% of the compressed entries are randomly
    # picked to be processed by the dead check (capped to 10,000 domains).
    # The results of the 50% is a good representation of the actual percentage
    # of dead domains (deviation of +-2%).
    [[ "$compressed_count" -le 1000 ]] && selection_percentage=100
    selection_percentage="${selection_percentage:-50}"
    selection_count="$(( $(wc -l < compressed.tmp) * selection_percentage / 100 ))"
    (( selection_count > 10000 )) && selection_count=10000
    shuf -n "$selection_count" compressed.tmp | sort -o selection.tmp

    # Remove domains found in Hagezi's dead domains file
    comm -12 dead_cache.tmp selection.tmp > known_dead.tmp
    dead_cache_count="$(wc -l < known_dead.tmp)"
    comm -23 selection.tmp known_dead.tmp > temp
    mv temp selection.tmp

    # Check for new dead domains using Dead Domains Linter
    sed -i 's/.*/||&^/' selection.tmp
    dead-domains-linter --dnscheck=false -i selection.tmp \
        --export dead_domains.tmp
    printf "\n" >> dead_domains.tmp

    # Calculate total dead
    dead_count="$(( $(wc -l < dead_domains.tmp) + dead_cache_count ))"
    dead_percentage="$(( dead_count * 100 / selection_count ))"

    # Check for invalid entries removed by Hostlist Compiler
    compile -i compressed.tmp compiled.tmp
    invalid_entries="$(comm -23 compressed.tmp compiled.tmp)"
    # Note wc -w miscounts lines with whitespaces as two or more words
    invalid_entries_count="$(wc -w <<< "$invalid_entries")"
    invalid_entries_percentage="$(( invalid_entries_count * 100 / compressed_count ))"

    # Check for domains in Tranco
    in_tranco="$(comm -12 compressed.tmp tranco.tmp)"
    in_tranco_count="$(wc -w <<< "$in_tranco")"

    # Calculate percentage of total usable compressed domains
    # The '100' here is 100% of the compressed blocklist
    usable_percentage="$(( 100 - dead_percentage \
        - invalid_entries_percentage ))"

    # Find unique and duplicate domains in other blocklists
    duplicates_table="| Unique | Blocklist |\n| ---:|:--- |\n"
    for blocklist in *_blocklist.tmp; do
        name="${blocklist%_blocklist.tmp}"
        # wc -l seems to work just fine here
        unique_count="$(comm -23 compressed.tmp "${name}_blocklist.tmp" | wc -l)"
        unique_percentage="$(( unique_count * 100 / compressed_count ))"
        duplicates_table="${duplicates_table}| ${unique_count} (${unique_percentage}%) | ${name} |\n"
    done

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
    replace DEAD_CACHE_COUNT "$dead_cache_count"

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
