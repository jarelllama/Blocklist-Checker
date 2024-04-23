# Jarelllama's Blocklist Checker

Generate a simple static report for DNS blocklists or see previous reports of requested blocklists.

**See all checked blocklists [here](https://github.com/jarelllama/Blocklist-Checker/issues?q=is%3Aissue+label%3A%22check+blocklist%22+label%3A%22report+generated%22+).**

## How to

1. Open a new issue: [Check a blocklist](https://github.com/jarelllama/Blocklist-Checker/issues/new/choose)
2. Enter the URL to the raw file of the blocklist
3. Wait a few minutes for the report to generate
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

These transformations remove redunant rules and strip modifiers to convert Adblock Plus rules to domains.

The percentage next to the count is the entries compressed from the total raw entries (a higher percentage means higher compression).

Note that the compressed blocklist is used for all further processing.

### Percentage of dead domains

The percentage of domains found unresolving by [AdGuard's Dead Domains Linter](https://github.com/AdguardTeam/DeadDomainsLinter).

To generate faster reports, only 60% of the compressed entries are selected for the dead check and used to calculate the percentage. This selection is done at random and capped at 10,000 domains.

### Invalid entries

The number of entries deemed invalid and removed by the Hostlist Compiler. Expanding the dropdown reveals the entries removed.

The following transformations are applied:

* RemoveComments
* Deduplicate
* Compress
* Validate
* TrimLines
* InsertFinalNewLine

These transformations remove non-domain entries like IP addresses and Unicode. Unicode in blocklists should be converted to Punycode for compatibility.

The percentage next to the count is the entries removed from the total compressed entries.

### Domains found in Tranco

The number of domains found in the [Tranco Top Sites Ranking](https://tranco-list.eu/). Expanding the dropdown reveals the domains found.

### Unique domains not found in other blocklists

The number of domains that were not found in the specified blocklist in column two. See the list of blocklists configured for comparison here: [blocklists_to_compare.txt](https://raw.githubusercontent.com/jarelllama/Blocklist-Checker/main/data/blocklists_to_compare.txt)

The percentage shows what percent of domains are unique to the blocklist being checked.

### Top 15 TLDs

The number of occurrences for the top 15 TLDs in the compressed entries.

### Processing time

Time taken in seconds to download the blocklist and generate the report.
