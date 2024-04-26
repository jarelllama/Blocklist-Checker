# Jarelllama's Blocklist Checker

Generate a simple static report for DNS blocklists or see previous reports of requested blocklists.

**View all blocklist reports [here](https://github.com/jarelllama/Blocklist-Checker/issues?q=is%3Aissue+label%3A%22report+generated%22).**

Feel free to request new features!

To check if a specific domain is present in a blocklist try:

* [dnswarden's search function](https://dnswarden.com/search.html)
* [AdGuard's urlfilter API](https://urlfilter.adtidy.org/#checkDomainInfo)

## How to

1. Open a new issue: [Check a blocklist](https://github.com/jarelllama/Blocklist-Checker/issues/new/choose)
2. Enter the URL to the raw file of the blocklist<br>
   **Supported formats: Domains, Adblock Plus, Hosts**
3. Make yourself a coffee or tea while the report generates
4. The GitHub Actions bot will reply with the report

See what is included in the report below.

## Report

### Number of raw entries

The number of entries in the blocklist calculated after removing comments and the `[Adblock Plus]` header.

### Number of compressed entries

The number of entries after compression via [AdGuard's Hostlist Compiler](https://github.com/AdguardTeam/HostlistCompiler).

The following [transformations](https://github.com/AdguardTeam/HostlistCompiler?tab=readme-ov-file#-transformations) are applied:

* RemoveComments
* Compress
* RemoveModifiers

These transformations remove redundant rules and strip modifiers to format the blocklist to domains.

The percentage next to the count is the entries compressed from the total raw entries (a higher percentage means higher compression).

Note that the compressed blocklist is used for all further processing.

### Percentage of dead domains

An estimate of the percentage of domains found unresolving by [AdGuard's Dead Domains Linter](https://github.com/AdguardTeam/DeadDomainsLinter).

For blocklists with more than 1000 compressed entries, only 50% of the domains are selected for the dead check and used to calculate the percentage. This selection is done at random and capped at 10,000 domains.

The selected domains provide a reasonable representation of the percentage of dead domains in the blocklist with a deviation of about ±2 while reducing processing time.

### Invalid entries

The number of entries deemed invalid and removed by the Hostlist Compiler. Expanding the dropdown reveals the entries removed (limited to 1000 entries).

The following transformations are applied:

* RemoveComments
* Deduplicate
* Compress
* Validate
* TrimLines
* InsertFinalNewLine

These transformations remove non-domain entries like IP addresses and Unicode. Unicode in blocklists should be converted to Punycode for compatibility.

The percentage next to the count is the entries removed from the total compressed entries.

### Percentage of usable compressed domains

An estimate of the percentage of potential domains that can be used in a DNS blocklist.

`domains usable = compressed entries - dead domains - invalid entries`

### Domains found in Tranco

The number of domains found in the [Tranco Top Sites Ranking](https://tranco-list.eu/). Expanding the dropdown reveals the domains found (limited to 1000 entries).

### Unique domains not found in other blocklists

The number of domains that were not found in the specified blocklist in column two. See the list of blocklists configured for comparison here: [blocklists_to_compare.txt](https://raw.githubusercontent.com/jarelllama/Blocklist-Checker/main/data/blocklists_to_compare.txt)

The percentage shows what percent of domains are unique to the blocklist being checked.

### Top 15 TLDs

The number of occurrences for the top 15 top-level domains (TLDs) in the compressed entries.

### Processing time

Time taken in seconds to download the blocklist and generate the report.

Note that the time taken to download dependencies/restore cache is excluded from this calculation.

