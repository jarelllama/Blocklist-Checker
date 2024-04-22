# Jarelllama's Blocklist Check

Description is WIP

## Report

### Number of domains

The number of entries in the blocklist calculated after processing through [AdGuard's Hostlist Compiler](https://github.com/AdguardTeam/HostlistCompiler) to standardize the format of the blocklist and to remove comments. This includes non-domain entries like IP addresses.

The following [transformations](https://github.com/AdguardTeam/HostlistCompiler?tab=readme-ov-file#-transformations) were applied:

* RemoveComments
* Compress[^1]

[^1]: Used to convert the various formats of blocklists to Adblock Plus syntax and then to Domains in order to standardize the format of the blocklist. Note that this removes redundant domains/rules which may affect the calculations.

### Entries removed by Hostlist Compiler

The number of entries removed by the Hostlist Compiler. Expanding the dropdown reveals the entries removed.

The following transformations were applied:

* RemoveComments
* Deduplicate
* Compress
* Validate
* TrimLines
* InsertFinalNewLine

These transformations remove non-domain entries like IP addresses and empty lines, along with Unicode. Unicode in blocklists should be converted to Punycode for compatibility.

The percentage next to the count is the entries removed from the total number of non-compiled entries (Number of domains).

Note that all further processing is done on the non-compiled blocklist with IP addresses and Unicode kept.

### Number of entries after compiling

The number of domains after processing through the Hostlist Compiler. This number is the same as `Number of domains - Entries removed by Hostlist Compiler`.

### Domains found in Tranco

The number of domains found in the [Tranco Top Sites Ranking](https://tranco-list.eu/). Expanding the dropdown reveals the domains found.

### Number of dead domains

The number of domains found dead by [AdGuard's Dead Domains Linter](https://github.com/AdguardTeam/DeadDomainsLinter).

To generate faster reports, only 60% of the blocklist is selected for the dead check. This selection is done at random using `shuf`.

The percentage next to the count is the dead domains removed from 60% of the total number of non-compiled entries (Number of domains).

### Unique domains not found in other blocklists

The count is of domains that were not found in the specified blocklist. See the list of blocklists configured to compare from here: [blocklists_to_compare.txt](https://raw.githubusercontent.com/jarelllama/Blocklist-Checker/main/data/blocklists_to_compare.txt)

The percentage is the domains that were not found in the specified blocklist from the total number of domains (Number of domains).

### Processing time

Time taken in seconds from downloading the blocklist to generating the report.
