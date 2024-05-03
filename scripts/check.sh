#!/bin/bash

# Generates a markdown report for the given blocklist.

readonly TEMPLATE='data/TEMPLATE.md'
readonly BLOCKLISTS_TO_COMPARE='data/blocklists_to_compare.txt'
readonly URL="$1"

main() {
    # Install AdGuard's Hostlist Compiler and Dead Domains Linter if not installed
    install_dependencies

    # Download necessary data files
    download_data

    # Process blocklist
    process_blocklist

    # Generate report
    generate_report
}

# Install dependencies if not already installed
install_dependencies() {
    install_if_not_installed "hostlist-compiler" "@adguard/hostlist-compiler"
    install_if_not_installed "dead-domains-linter" "@adguard/dead-domains-linter"
}

# Install a package if the corresponding command is not available
install_if_not_installed() {
    local command_name=$1
    local package_name=$2
    if ! command -v "$command_name" &> /dev/null; then
        npm install -g "$package_name"
    fi
}

# Download necessary data files
download_data() {
    download_file "dead_cache.tmp" "https://github.com/hagezi/dns-blocklists/raw/main/share/dead.list-a[a-f]"
    download_file "tranco.tmp" "https://tranco-list.eu/top-1m.csv.zip" "--retry 2 --retry-all-errors | gunzip -"
    while read -r blocklist; do
        name=$(cut -d ',' -f 1 <<< "$blocklist")
        url=$(cut -d ',' -f 2 <<< "$blocklist")
        download_file "${name}_blocklist.tmp" "$url"
    done < <(sort "$BLOCKLISTS_TO_COMPARE")
}

# Download a file if it does not exist
download_file() {
    local filename=$1
    local url=$2
    local curl_options=${3:-""}
    if [[ ! -f "$filename" ]]; then
        curl -L $curl_options "$url" -o "$filename"
    fi
}

# Process blocklist
process_blocklist() {
    # Download blocklist and exit if errored
    curl -L "$URL" -o raw.tmp || exit 1

    # Preprocess raw blocklist
    preprocess_blocklist

    # Count number of raw uncompressed entries
    raw_count=$(wc -l < raw.tmp)

    # Compress and compile blocklist
    compile_blocklist

    # Further processing
    further_processing
}

# Preprocess raw blocklist
preprocess_blocklist() {
    sed -i 's/\r//g; /^$/d; s/[[:space:]]*$//' raw.tmp
    title=$(mawk -F 'Title: ' '/Title:/ {print $2}' raw.tmp | head -n 1)
    title=${title:-$URL}
    mawk '!/[\[#!]/ {print tolower($0)}' raw.tmp | sort -o raw.tmp
}

# Compile blocklist using AdGuard's Hostlist Compiler
compile_blocklist() {
    create_hostlist_compiler_config
    compile -c config.json compressed.tmp
}

# Further processing steps
further_processing() {
    # Count number of compressed entries
    compressed_count=$(wc -l < compressed.tmp)
    compression_percentage=$(( (raw_count - compressed_count) * 100 / raw_count ))

    # To reduce processing time, 50% of the compressed entries are randomly
    # picked to be processed by the dead check (capped to 10,000 domains).
    # The results of the 50% is a good representation of the actual percentage
    # of dead domains (deviation of +-2%).
    [[ "$compressed_count" -le 1000 ]] && selection_percentage=100
    selection_percentage="${selection_percentage:-50}"
    selection_count=$(( compressed_count * selection_percentage / 100 ))
    (( selection_count > 10000 )) && selection_count=10000
    shuf -n "$selection_count" compressed.tmp | sort -o selection.tmp

    # Remove domains found in Hagezi's dead domains file
    comm -12 dead_cache.tmp selection.tmp > known_dead.tmp
    dead_cache_count=$(wc -l < known_dead.tmp)
    comm -23 selection.tmp known_dead.tmp > temp
    mv temp selection.tmp

    # Check for new dead domains using Dead Domains Linter
    sed -i 's/.*/||&^/' selection.tmp
    dead-domains-linter -i selection.tmp --export dead_domains.tmp
    printf "\n" >> dead_domains.tmp

    # Calculate total dead
    dead_count=$(( $(wc -l < dead_domains.tmp) + dead_cache_count ))
    dead_percentage=$(( dead_count * 100 / selection_count ))

    # Check for invalid entries removed by Hostlist Compiler
    compile -i compressed.tmp compiled.tmp
    invalid_entries=$(comm -23 compressed.tmp compiled.tmp)
    # Note wc -w miscounts lines with whitespaces as two or more words
    invalid_entries_count=$(wc -w <<< "$invalid_entries")
    invalid_entries_percentage=$(( invalid_entries_count * 100 / compressed_count ))

    # Check for domains in Tranco
    in_tranco=$(comm -12 compressed.tmp tranco.tmp)
    in_tranco_count=$(wc -w <<< "$in_tranco")

    # Calculate percentage of total usable compressed domains
    usable_percentage=$(( 100 - dead_percentage - invalid_entries_percentage ))

    # Find unique and duplicate domains in other blocklists
    comparison_table="| Unique | Blocklist |\n| ---:|:--- |\n"
    for blocklist in *_blocklist.tmp; do
        name="${blocklist%_blocklist.tmp}"
        unique_count=$(comm -23 compressed.tmp "${name}_blocklist.tmp" | wc -l)
        unique_percentage=$(( unique_count * 100 / compressed_count ))
        comparison_table="${comparison_table}| ${unique_count} **(${unique_percentage}%)** | ${name} |\n"
    done

    # Get the top TLDs
    tlds=$(mawk -F '.' '{print $NF}' compressed.tmp | sort | uniq -c \
        | sort -nr | head -n 15)
}

# Compile blocklist using Hostlist Compiler
compile() {
    hostlist-compiler "$1" "$2" -o temp
    mawk '/^[|]/ {gsub(/[|^]/, "", $0); print $0}' temp | sort -u -o "$3"
}

# Generate report
generate_report() {
    title=${title//&/\\&}  # Escape '&'
    replace TITLE "${title//[\/]/\\/}"  # Escape slashes
    replace URL "${URL//[\/]/\\/}"  # Escape slashes
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
    replace COMPARISON_TABLE "$comparison_table"
    replace TLDS "$tlds"
    replace PROCESSING_TIME "$(( $(date +%s) - execution_time ))"
    replace GENERATION_TIME "$(date -u)"
    replace DEAD_CACHE_COUNT "$dead_cache_count"
}

# Function 'replace' updates the markdown template with values from the
# results. Note that only the first occurrence in the file is replaced.
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

# Create configuration file for Hostlist Compiler
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

# Entry point of the script
main
