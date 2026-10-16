# MT5 Zone Recovery Expert Advisor

[![Core regression checks](https://github.com/NadirAliOfficial/mt5-zone-recovery/actions/workflows/checks.yml/badge.svg)](https://github.com/NadirAliOfficial/mt5-zone-recovery/actions/workflows/checks.yml)
[![Platform: MetaTrader 5](https://img.shields.io/badge/platform-MetaTrader_5-2563eb)](https://www.metatrader5.com/)
[![Language: MQL5](https://img.shields.io/badge/language-MQL5-0f766e)](https://www.mql5.com/en/docs)
[![Tools: Python CLI](https://img.shields.io/badge/tools-Python_CLI-f59e0b)](tools/mt5_cli.py)

**MT5 Zone Recovery** is a MetaTrader 5 Expert Advisor written in **MQL5**, with two-level hedging, adjustable lot multiplication, basket take profit, and command-line research tools. It combines the MT5 EA source and compiled EX5 with a native compiler workflow, historical bid/ask tick export, and an independent Python backtesting replay.

**Research status:** the EA compiles with zero errors/warnings, and 38 local checks passed. Every reported historical replay setting lost money. Native MT5 Strategy Tester execution remains unverified in the test environment. Read the [measured results and limitations](reports/RESULTS.md) before evaluating the strategy.

## Features

- **Two-level zone recovery:** random initial buy/sell, then alternating hedge entries at fixed levels.
- **Adjustable lot multiplier:** 1.5×, 2×, 3× or another value greater than one, with broker-step rounding.
- **Basket take profit:** fixed USD or equivalent-point targets, plus either/both modes.
- **Fixed or automatic starting lot:** optional balance-based volume, such as .01 lots per 1,000 account-currency units.
- **Trade and lot limits:** stop adding recovery legs at configured limits while monitoring the basket.
- **Execution safeguards:** symbol/magic isolation, spread filtering, fill return-code checks, persisted state, and a liquidation retry latch.
- **CLI tooling:** compile MQL5, request native tester runs, export historical ticks, and run independent replays.
- **Transparent evidence:** source, compiled binary, test fixtures, dataset hash, settings, and loss-inclusive reports.

Requires a **hedging account**; netting accounts are unsupported. The strategy uses no indicators or timeframe signals. Lot multiplication increases exposure, and trade/lot limits do not cap losses.

## Contents

[Quick start](#quick-start) · [Strategy](#strategy) · [Basket targets](#target-modes-and-costs) · [Inputs](#inputs) · [Execution limits](#execution-restarts-and-limitations) · [Compile and test](#install-and-compile) · [Historical results](#measured-validation-and-historical-replay) · [Project structure](#project-structure) · [Contributing](#contributing)

## Quick start

1. Clone the repository:

   ```sh
   git clone https://github.com/NadirAliOfficial/mt5-zone-recovery.git
   cd mt5-zone-recovery
   ```

2. Copy the contents of `MQL5/` to an isolated MetaTrader 5 test installation's `MQL5/` folder.
3. Open `MQL5/Experts/ZoneRecovery/ZoneRecovery.mq5` in MetaEditor and compile it, or use the CLI below.
4. Review `configs/eurusd-dollars.ini` and the [input settings](#inputs). Test with a demo hedging account and your broker's symbol specifications.

Windows CLI example, using an existing saved demo login:

```powershell
python tools/mt5_cli.py --terminal C:\MT5-Test compile
python tools/mt5_cli.py --terminal C:\MT5-Test test configs/eurusd-dollars.ini --login YOUR_SAVED_DEMO_LOGIN
```

The EA defaults to `InpEnableTradingOutsideTester=false`, so attaching the default configuration to a chart does not enable trading. See [installation and compilation](#install-and-compile) for Wine/macOS options.

## Research results at a glance

Independent EURUSD bid/ask replay, January–March 2025, initial balance **$1,000**, seed 42:

| Lot multiplier | Ending balance | Net P/L | Maximum equity drawdown |
|---|---:|---:|---:|
| 1.5× | $728.91 | −$271.09 | 36.35% |
| 2× | $413.48 | −$586.52 | 75.42% |
| 3× | $212.64 | −$787.36 | 82.30% |

These are **independent replay results, not native MT5 Strategy Tester results**. The 3× run hit the simulated stop-out threshold before the end of the period. Other runs include liquidation of unresolved positions at the final quote. Assumptions include $7/lot round-turn commission, zero swap/slippage/delay, and conservative gross margin. [Full settings, data provenance, and limitations →](reports/RESULTS.md)

## Strategy

1. With no own positions, choose BUY or SELL using a seeded random generator. Use a fixed starting lot or `balance / capital_per_lot_unit * lot_unit`.
2. Close a lone initial trade when its executable close price has moved `InitialTPPoints` favorably from its fill and its net P/L is positive. Begin a new cycle on a later tick.
3. If the market reverses `GridPoints` from the first bid reference, keep the original position and open an opposite leg. Alternate between the original two bid levels; do not shift a trailing grid along the trend.
4. Multiply the **last executed lot** for each new leg. Round **up** to the broker's volume step. Thus 2× gives .01, .02, .04, .08, .16; 1.5× at .01 step gives .01, .02, .03, .05, .08. This implementation multiplies every successive leg without intentionally repeating lot sizes.
5. After the second leg, use a basket target instead of the initial trade target. Close own positions by ticket and restart only when all close requests have succeeded.
6. Max trades or max lot stops further entries for that basket. Existing positions remain open and eligible for basket closure. These limits **do not cap financial loss**. A basket can remain unresolved indefinitely.

## Target modes and costs

- `TARGET_DOLLARS`: fixed basket target in USD; requires a USD-denominated account.
- `TARGET_POINTS`: fixed **net basket equivalent points**, defined as `net basket P/L / cash value of one broker point at this cycle's initial lot`. This is explicit because a hedged basket has no single trade's entry price. It is not a sum of unweighted trade points, nor the distance from the most recent trade.
- `TARGET_EITHER`: close when either target is reached.
- `TARGET_BOTH`: close only when both are reached.

Both numerical targets are independent inputs; neither rises with trade count. The points definition is an explicit implementation choice; review it when comparing this EA with other basket-target systems.

P/L includes MT5 floating profit, position swap, and paid deal commission/fees for open position IDs. `ExitCommissionPerLot` deducts an estimate of remaining close costs; set it for the broker. Exact future fills/fees are unknowable. Spread enters through actual bid/ask P/L. Sequential market closes are not simultaneous or atomic; slippage can change the final realized result.

## Inputs

| Input | Default | Meaning |
|---|---:|---|
| StartingLot | 0.01 | Fixed initial volume |
| AutoLot | false | Balance-based first volume, recalculated at each new cycle |
| CapitalPerLotUnit / LotUnit | 1000 / .01 | Auto lot ratio in account currency |
| Multiplier | 2 | Any value greater than 1, including 1.5 / 2 / 3 |
| GridPoints / InitialTPPoints | 200 / 200 | Broker points, not pips |
| TargetMode | Dollars | Dollars, points, either, both |
| BasketDollars / BasketPoints | 2 / 200 | Fixed thresholds |
| MaxTrades / MaxLot | 5 / 1 | Stops new legs at limits; does not liquidate |
| MaxSpreadPoints | 50 | Entry filter only; exits remain active |
| ExitCommissionPerLot | 0 | Estimated remaining close cost per lot |
| DeviationPoints | 20 | Requested market-order deviation |
| Magic | 16102026 | Use a unique number per independent instance |
| RandomSeed | 42 | Reproducible seed; 0 seeds from local time |
| EnableTradingOutsideTester | false | Explicit opt-in required for chart trading |

Defaults are demonstration settings, not selected or optimized for profitability. The included EURUSD and account-size settings are research examples; all historical test settings are disclosed in the reports.

## Execution, restarts, and limitations

- Manages only the current symbol and magic. One chart per symbol/magic, with a terminal-global ownership lock.
- Uses bid levels for both reversal triggers, and actual bid/ask for trade exits. On a gap, opens at the available market price, not an invented historical trigger fill.
- Stores basket state in terminal globals after fills and before liquidation. A restart with missing/inconsistent state refuses initialization. Do not change strategy inputs during an open basket.
- A manual/external change in own position count or total volume halts automatic management for inspection (except an already-latched liquidation, which continues). After manually closing all positions, the halt persists. To clear it, remove the EA, ensure the basket is flat, and delete only that instance's `ZRE.<login>.<symbol>.<magic>.` terminal globals before reattaching.
- Partial entry fills stop further recovery additions; current positions remain managed. Broker rejections are logged. There is no stop loss or emergency equity cutoff in the requested logic.
- The EA submits market orders on observed ticks. It has no server-side protective orders, so the terminal must remain connected and running.
- Rounding up can increase exposure faster than the exact mathematical multiplier. Volumes outside broker/user limits are refused rather than silently capped.
- Restart safeguards cannot make order execution and terminal-global persistence atomic across a crash. Inspect an inconsistent basket before resuming.

## Install and compile

Copy the contents of `MQL5/` into an **isolated** MT5 portable terminal's `MQL5/` directory. Compile `Experts/ZoneRecovery/ZoneRecovery.mq5` with MetaEditor. Standard `Trade` includes are supplied by MT5. The compiled `.ex5` is included after verified compilation.

Native Windows CLI:

```powershell
python tools/mt5_cli.py --terminal C:\MT5-Test compile
python tools/mt5_cli.py --terminal C:\MT5-Test test configs/eurusd-dollars.ini --login YOUR_SAVED_DEMO_LOGIN
```

macOS uses the Wine bundled with the installed MT5 app. Set the terminal and Wine-prefix paths to your own isolated test setup:

```sh
python3 tools/mt5_cli.py --terminal /path/to/isolated/mt5 \
  --wine '/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wine64' \
  --wine-prefix '/path/to/mt5/wine-prefix' compile
# Use the same options, replacing `compile` with:
# test configs/eurusd-dollars.ini --login YOUR_SAVED_DEMO_LOGIN
```

A saved demo account is needed by this installed MT5 build to initialize the tester and obtain broker history/specifications. Credentials are not part of this repository. Use local agents only; paid cloud agents are disabled. The CLI treats the compiler result and a new HTML report as evidence, not Wine's exit code.

Shared-core tests compile the **same shipped `.mqh` arithmetic/trigger functions**, using C++ math aliases; they do not replace native MT5 execution:

```sh
c++ -std=c++17 -Wall -Wextra -Werror tests/core_test.cpp -o /tmp/zr-core-test
/tmp/zr-core-test
```

On macOS, use a matching compiler/SDK if the system command-line SDK is newer than the linker. Tests cover lot rounding, limits, auto-lot arithmetic, alternating triggers, target modes, and recovery profit/loss arithmetic.

## Measured validation and historical replay

The EA compiles natively in MetaEditor with zero errors/warnings. There are 32 shared-core checks plus six economic replay fixtures. The **native Strategy Tester did not dispatch a job** in this isolated Wine environment, so no native tester financial report is claimed. The reported financial results come from the independent Python replay, using 3,936,375 EURUSD bid/ask ticks exported read-only by MT5 for January–March 2025.

Export the fixed research date range (2025-01-02 through 2025-03-31) using a saved MetaQuotes demo context:

```sh
python3 tools/mt5_cli.py --terminal /path/to/test/terminal [Wine options] export --login YOUR_SAVED_DEMO_LOGIN
python3 tools/replay.py /path/to/test/terminal/MQL5/Files/zr-eurusd-ticks.csv \
  --multiplier 2 --mode dollars --commission 7 --seed 42 --output reports/replay-baseline.json
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

`[Wine options]` means the actual `--wine` and `--wine-prefix` options shown above; omit those on Windows. The exporter overwrites its named CSV in the test terminal. Raw tick data and saved-account configuration are deliberately excluded from Git. The replay assumes $7/lot round-turn commission, zero swap/slippage/delay, conservative gross margin, and liquidation of residual exposure at the last quote. These are research assumptions, **not broker execution or fee verification**. MT5 account/broker validation is still required, including restart/partial-fill/manual-interference behavior.

See `reports/RESULTS.md` for measured results and test limitations. Treat the robot as a technical implementation for review; historical results do not establish future profitability.

## Project structure

```text
MQL5/
  Experts/ZoneRecovery/   EA source (.mq5) and compiled binary (.ex5)
  Include/ZoneRecovery/   Shared strategy arithmetic and trigger functions
  Scripts/                   Read-only historical tick exporter
configs/                     EURUSD native tester configuration examples
reports/                     Results, replay JSON, compiler evidence, hashes
tests/                      Shared-core C++ checks and Python replay fixtures
tools/                      Compile/export/test CLI and tick replay engine
```

`HANDOVER.md` records implementation decisions and outstanding integration checks. Raw broker tick files, account credentials, and private terminal configuration are excluded.

## Contributing

[Report a bug](https://github.com/NadirAliOfficial/mt5-zone-recovery/issues/new) with the MT5 build, hedging-account type, symbol specification, EA input settings, expected behavior, and a minimal reproducible case. Remove account identifiers and credentials from logs before sharing them.

For changes, run the C++ core checks and Python replay tests described above. Keep native MT5 execution evidence separate from independent replay results. Strategy changes should include a clear explanation of how they alter entry levels, lot sizes, costs, or basket exits.

## Official references

- [MT5 command-line configuration and tester parameters](https://www.metatrader5.com/en/terminal/help/start_advanced/start)
- [Ticket-based close and server return-code checks](https://www.mql5.com/en/docs/standardlibrary/tradeclasses/ctrade/ctradepositionclose)
