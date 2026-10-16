# Validation and backtest results

Verified on 2026-10-16 (Asia/Karachi).

## What passed

- Native MetaEditor compilation: **0 errors, 0 warnings**; MT5 build 6140 under Wine 10, Windows 10 compatibility.
- **32 shared-core C++ checks** against the shipped MQL include functions.
- **6 replay accounting/execution fixtures**: initial bid/ask TP, recovery loss and spread, round-turn costs, fixed point/dollar equivalence, trade cap, and forced realization of unresolved loss.
- Read-only native MT5 export: **3,936,375 EURUSD bid/ask ticks**, requested 2025-01-02 through 2025-03-31, using MetaQuotes-Demo history. `CopyTicksRange` exports broker history; it does not synthesize ticks.

## Financial results — independent replay, not native MT5 Strategy Tester

All runs start at **$1,000**, starting lot .01, grid and initial TP 200 broker points, basket target $2 (or 200 initial-lot-equivalent points), max five trades, max lot 1, spread filter 50 points, seed 42. No optimization was performed.

| Multiplier / target | Ending balance | Net P/L | Maximum equity drawdown | Baskets (wins/losses) | End condition |
|---|---:|---:|---:|---:|---|
| 1.5× / dollars | $728.91 | $-271.09 | 36.35% | 22 (21/1) | 5 open trades liquidated at final quote |
| 2× / dollars | $413.48 | $-586.52 | 75.42% | 48 (47/1) | 5 open trades liquidated at final quote |
| 2× / points | $413.48 | $-586.52 | 75.42% | 48 (47/1) | 5 open trades liquidated at final quote |
| 3× / dollars | $212.64 | $-787.36 | 82.30% | 79 (78/1) | Simulated margin stop-out |

The 3× run stops at dataset timestamp **2025-03-05 11:03:50**; tick times are exported MT5 history timestamps without a verified broker timezone. It processes 2,530,998 ticks before the modeled stop-out, rather than the entire quarter. Its fifth leg is refused by the replay's conservative margin check, leaving four positions. Other runs process every exported tick. Dollar and point targets match here because 200 equivalent points at a .01 EURUSD initial lot equal $2 under the assumed contract size.

A high fraction of winning baskets does not make this strategy profitable. The 2× run closes 47 profitable baskets, but its last unresolved basket erases those gains. Its longest basket lasts roughly 56.9 days. Results include losses from final liquidation; no open losses are hidden behind a realized-balance-only total.

## Modeling assumptions and limitations

- Actual exported bid/ask quotes, with **$7 per lot round-turn commission assumed**, half charged at entry and half at exit. This is a research cost assumption, not a verified broker tariff.
- **Zero swap, zero slippage, zero execution delay**, immediate full fills, and atomic simulated basket exits. Real EA exits are sequential ticket-based market closes and can differ materially.
- Contract size 100,000; point .00001; lot step .01. These match the native exporter metadata for this dataset.
- Margin modeled conservatively as **gross notional / 100** leverage. This is not MT5's native hedged-margin implementation. Simulated stop-out liquidates the entire basket at a 50% margin level; broker liquidation rules can differ.
- Remaining positions are liquidated at the final available bid/ask. This research end-date liquidation is not a scheduled exit feature in the EA.
- Replay is an independent model of the strategy. It does not execute the compiled EX5 and is not proof of exact platform behavior. The shared-core tests exercise common arithmetic and triggers, not all broker execution paths.
- Native tester initialization and demo synchronization succeeded, but the tester never dispatched a run to an agent in the isolated Wine environment. **No native MT5 backtest report, performance figures, or native execution validation is claimed.** See `native-tester-status.txt`.
- Restart recovery, partial fills, uncertain order outcomes, and manual-interference safeguards are implemented but still require native broker/demo integration testing.
- The source implements bid-coordinate reversal levels, upward volume rounding, initial-lot-equivalent basket points, and optional either/both target modes. These interpretations need the client's acceptance before final delivery.
- One symbol, one period, one random seed, and three multiplier settings are reported. No robustness or future-profitability claim is made.

## Evidence and reproduction

- `compile.txt`: native EA compiler result.
- `data-export.txt`: per-day broker tick counts and final export metadata.
- `validation.txt`: shared-core and economic fixture results.
- `replay-*.json`: complete settings, data hash, and numerical results for every run.
- `manifest.json`: SHA-256 hashes tying source, compiled EA, core functions, replay engine, and dataset to this report.
- `../tools/mt5_cli.py`: compile, read-only export, and native tester commands.
- `../tools/replay.py`: independent replay command.

Raw broker ticks, account databases, API keys, client chat, and private terminal configuration are excluded from the repository and delivery ZIP. Repeat broker tests in an isolated terminal before enabling chart trading. The default EA refuses trading outside the tester unless explicitly enabled.

## GitHub check status

Public repository: https://github.com/NadirAliOfficial/mt5-zone-recovery. The first Actions run ([38834089865](https://github.com/NadirAliOfficial/mt5-zone-recovery/actions/runs/38834089865)) could not start: “The job was not started because an Actions budget is preventing further use.” After public publication, [Actions run 38866735794](https://github.com/NadirAliOfficial/mt5-zone-recovery/actions/runs/38866735794) passed the core regression and replay checks. Local validation output is retained in `validation.txt`. No billing settings were changed.
