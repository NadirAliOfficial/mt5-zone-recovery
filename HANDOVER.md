# Handover — MT5 Zone Recovery MT5

Updated: 2026-10-16 (Asia/Karachi).

## Completed
- Project renamed to `mt5-zone-recovery` at the user's request; current project branding, source/compiled filenames, include paths, trade comments, state prefix, CLI filenames, documentation and links use neutral Zone Recovery names. Native EA rebuilt with zero errors/warnings; all 38 checks passed again.
- The first public Actions run 38866735794 passed; the earlier private-account budget failure is historical.
- User explicitly requested public visibility and README/discovery improvements. Repository is now public; added a descriptive About summary, 17 relevant topics, a results homepage link, README badges/overview/quick start/results/navigation/contributing, and manual CI dispatch support.
- Existing source, compiled EA, and numerical research results are unchanged. Committed history scanned for credential patterns and excluded private files before public exposure.
- Built the MT5 hedging EA in `MQL5/Experts/ZoneRecovery/`, with shared arithmetic in `MQL5/Include/ZoneRecovery/`.
- Native MetaEditor compilation passed with zero errors and zero warnings; compiled EX5 included.
- Added reproducible CLI tools, four tester configurations, a read-only tick exporter, 32 shared-core checks, six economic replay fixtures, and GitHub Actions checks.
- Exported 3,936,375 native EURUSD bid/ask ticks for January–March 2025. Raw data stays outside this repository.
- Ran independent bid/ask replays for 1.5×, 2×, 3× and dollar/point equivalence. Results, assumptions, and hashes are in `reports/RESULTS.md` and adjacent JSON/text files.
- From $1,000: final balances $728.91 (1.5×), $413.48 (2×), $212.64 (3×). The 3× replay stops out under its modeled margin rules; other runs include forced end-date liquidation. These are simulated results, not native Strategy Tester figures.

## Rules and decisions
- User authorized building, CLI backtesting, and pushing to GitHub. Source, binary, tests, and results pushed to verified public repository: https://github.com/NadirAliOfficial/mt5-zone-recovery (main).
- Client confirmed adjustable multiplier and fixed basket target with dollar and point options.
- Implemented random first entry, two fixed bid-coordinate levels, strict multiplication of previous filled lot, broker-step rounding upward, initial trade TP, shared basket exits, fixed/auto initial lot, max trades/max lot, and restart/liquidation state.
- Basket points mean net P/L divided by the value of one broker point at the initial lot. Dollar/point/either/both modes included. USD accounts required for dollar modes.
- At limits, stop adding and keep managing existing basket. Manual/external position-count or total-volume changes halt management for inspection; an already-latched liquidation continues.
- No EA chart trading outside the tester by default. No live deployment, client message, or order change authorized/performed.
- Do not publish account databases, terminal configuration, raw broker ticks, API keys, or client conversation. Do not save secrets.

## Validation limits / remaining work
- Initial private Actions run 38834089865 was blocked by budget. Public run 38866735794 subsequently passed. No billing settings changed.
- The native tester starts and connects to a saved hedging demo context but never dispatches a test job under this isolated Wine setup. No native financial report exists. Native compilation and read-only tick export did work.
- Native tester/demo integration checks remain required for execution, restart recovery, partial fills, and manual interference. Replay has zero swap/slippage/delay and conservative gross margin; see full assumptions.
- Client acceptance is still needed for the explicit point-target definition, two-level bid triggers, upward rounding, and limit behavior. Client symbol/account/test settings were unspecified; EURUSD/$1,000/1:100/seed42 were research settings.
- Future continuation: read this handover and README first; verify external GitHub state before claims or changes. Update this handover at completion.
