# Jarelllama's Blocklist Check

Description is WIP

## Report

### Number of raw entries

The number of entries[^1] in the blocklist calculated after removing comments and the `[Adblock Plus]` header.

### Number of compressed entries

The number of entries after compression via [AdGuard's Hostlist Compiler](https://github.com/AdguardTeam/HostlistCompiler).

### Invalid entries

The number of entries deemed invalid and removed by the Hostlist Compiler. Expanding the dropdown reveals the entries removed.

The following [transformations](https://github.com/AdguardTeam/HostlistCompiler?tab=readme-ov-file#-transformations) were applied:

* RemoveComments
* Deduplicate
* Compress
* Validate
* TrimLines
* InsertFinalNewLine

These transformations remove non-domain entries like IP addresses and empty lines, along with Unicode. Unicode in blocklists should be converted to Punycode for compatibility.

The percentage next to the count is the entries removed from the total compressed entries.

### Domains found in Tranco

The number of domains in the raw blocklist found in the [Tranco Top Sites Ranking](https://tranco-list.eu/). Expanding the dropdown reveals the domains found.

### Percentage of dead domains

The percentage of domains found unresolving by [AdGuard's Dead Domains Linter](https://github.com/AdguardTeam/DeadDomainsLinter).

To generate faster reports, only 60% of the compressed entries are selected for the dead check and used to calculate the percentage. This selection is done at random.

### Unique domains not found in other blocklists

The number of domains[^1] in the raw blocklist that were not found in the specified blocklist in column 2. See the list of blocklists configured for comparison here: [blocklists_to_compare.txt](https://raw.githubusercontent.com/jarelllama/Blocklist-Checker/main/data/blocklists_to_compare.txt)

The percentage shows what percent of domains in the raw blocklist are unique.

### Processing time

Time taken in seconds from downloading the blocklist to generating the report.

[^1]: The raw blocklist may contain non-domain entries like IP addresses.
