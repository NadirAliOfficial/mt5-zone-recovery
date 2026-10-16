# Aziz Zone Recovery — MT5

MT5 Expert Advisor implementing random first entry and alternating hedged recovery at **two fixed levels**, with a configurable multiplier and fixed net basket target. Requires a **hedging account**. No indicators or timeframe signals.

## Strategy

1. With no own positions, choose BUY or SELL using a seeded random generator. Use a fixed starting lot or `balance / capital_per_lot_unit * lot_unit`.
2. Close a lone initial trade when its executable close price has moved `InitialTPPoints` favorably from its fill and its net P/L is positive. Begin a new cycle on a later tick.
3. If the market reverses `GridPoints` from the first bid reference, keep the original position and open an opposite leg. Alternate between the original two bid levels; do not shift a trailing grid along the trend.
4. Multiply the **last executed lot** for each new leg. Round **up** to the broker's volume step. Thus 2× gives .01, .02, .04, .08, .16; 1.5× at .01 step gives .01, .02, .03, .05, .08. The duplicated lots in the supplied diagrams are treated as diagram errors.
5. After the second leg, use a basket target instead of the initial trade target. Close own positions by ticket and restart only when all close requests have succeeded.
6. Max trades or max lot stops further entries for that basket. Existing positions remain open and eligible for basket closure. These limits **do not cap financial loss**. A basket can remain unresolved indefinitely.

## Target modes and costs

- `TARGET_DOLLARS`: fixed basket target in USD; requires a USD-denominated account.
- `TARGET_POINTS`: fixed **net basket equivalent points**, defined as `net basket P/L / cash value of one broker point at this cycle's initial lot`. This is explicit because a hedged basket has no single trade's entry price. It is not a sum of unweighted trade points, nor the distance from the most recent trade.
- `TARGET_EITHER`: close when either target is reached.
- `TARGET_BOTH`: close only when both are reached.

Both numerical targets are independent inputs; neither rises with trade count. The chosen points definition and selectable/combined modes are implementation assumptions pending client acceptance.

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

Defaults are demonstration settings, not selected or optimized for profitability. No symbol or account size was specified by the client; historical test settings are disclosed in the reports.

## Execution, restarts, and limitations

- Manages only the current symbol and magic. One chart per symbol/magic, with a terminal-global ownership lock.
- Uses bid levels for both reversal triggers, and actual bid/ask for trade exits. On a gap, opens at the available market price, not an invented historical trigger fill.
- Stores basket state in terminal globals after fills and before liquidation. A restart with missing/inconsistent state refuses initialization. Do not change strategy inputs during an open basket.
- A manual/external change in own position count or total volume halts automatic management for inspection (except an already-latched liquidation, which continues). After manually closing all positions, the halt persists. To clear it, remove the EA, ensure the basket is flat, and delete only that instance's `AZR.<login>.<symbol>.<magic>.` terminal globals before reattaching.
- Partial entry fills stop further recovery additions; current positions remain managed. Broker rejections are logged. There is no stop loss or emergency equity cutoff in the requested logic.
- The EA submits market orders on observed ticks. It has no server-side protective orders, so the terminal must remain connected and running.
- Rounding up can increase exposure faster than the exact mathematical multiplier. Volumes outside broker/user limits are refused rather than silently capped.
- Restart safeguards cannot make order execution and terminal-global persistence atomic across a crash. Inspect an inconsistent basket before resuming.

## Install and compile

Copy the contents of `MQL5/` into an **isolated** MT5 portable terminal's `MQL5/` directory. Compile `Experts/AzizZoneRecovery/AzizZoneRecovery.mq5` with MetaEditor. Standard `Trade` includes are supplied by MT5. The compiled `.ex5` is included after verified compilation.

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
c++ -std=c++17 -Wall -Wextra -Werror tests/core_test.cpp -o /tmp/aziz-core-test
/tmp/aziz-core-test
```

On macOS, use a matching compiler/SDK if the system command-line SDK is newer than the linker. Tests cover lot rounding, limits, auto-lot arithmetic, alternating triggers, target modes, and the incorrect recovery arithmetic in the client's diagram.

## Measured validation and historical replay

The EA compiles natively in MetaEditor with zero errors/warnings. There are 32 shared-core checks plus six economic replay fixtures. The **native Strategy Tester did not dispatch a job** in this isolated Wine environment, so no native tester financial report is claimed. The reported financial results come from the independent Python replay, using 3,936,375 EURUSD bid/ask ticks exported read-only by MT5 for January–March 2025.

Export the fixed research date range (2025-01-02 through 2025-03-31) using a saved MetaQuotes demo context:

```sh
python3 tools/mt5_cli.py --terminal /path/to/test/terminal [Wine options] export --login YOUR_SAVED_DEMO_LOGIN
python3 tools/replay.py /path/to/test/terminal/MQL5/Files/aziz-eurusd-ticks.csv \
  --multiplier 2 --mode dollars --commission 7 --seed 42 --output reports/replay-baseline.json
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

`[Wine options]` means the actual `--wine` and `--wine-prefix` options shown above; omit those on Windows. The exporter overwrites its named CSV in the test terminal. Raw tick data and saved-account configuration are deliberately excluded from Git. The replay assumes $7/lot round-turn commission, zero swap/slippage/delay, conservative gross margin, and liquidation of residual exposure at the last quote. These are research assumptions, **not broker execution or fee verification**. MT5 account/broker validation is still required, including restart/partial-fill/manual-interference behavior.

See `reports/RESULTS.md` for measured results and test limitations. Treat the robot as a technical implementation for review; historical results do not establish future profitability.

## Official references

- [MT5 command-line configuration and tester parameters](https://www.metatrader5.com/en/terminal/help/start_advanced/start)
- [Ticket-based close and server return-code checks](https://www.mql5.com/en/docs/standardlibrary/tradeclasses/ctrade/ctradepositionclose)
