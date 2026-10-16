#!/usr/bin/env python3
"""Independent bid/ask tick replay. NOT the native MT5 Strategy Tester."""
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path


def replay(path, multiplier=2.0, mode='dollars', seed=42, commission=7.0):
    initial = balance = peak = 1000.0
    point, contract, leverage = 0.00001, 100000.0, 100.0
    positions = []
    cycles = []
    blocked = False
    upper = lower = base = 0.0
    rng = seed
    max_dd = max_dd_pct = max_volume = 0.0
    max_legs = limited_baskets = 0
    margin_rejections = stopouts = 0
    count = first_time = last_time = 0
    limit_noted = False
    start_time = 0
    last_bid = last_ask = 0.0

    def floating(bid, ask):
        return sum((bid - price if direction == 1 else price - ask) * contract * lots
                   for direction, lots, price in positions)

    def close(bid, ask, timestamp, reason):
        nonlocal balance, positions, blocked, limit_noted
        volume = sum(lots for _, lots, _ in positions)
        pnl = floating(bid, ask)
        balance += pnl - commission / 2 * volume
        cycles.append({'net': round(pnl - commission * volume, 8),
                       'legs': len(positions), 'reason': reason,
                       'duration_seconds': (timestamp - start_time) / 1000})
        positions = []
        blocked = limit_noted = False

    with path.open(newline='') as handle:
        for row in csv.DictReader(handle):
            timestamp = int(row['time_msc'])
            bid, ask = float(row['bid']), float(row['ask'])
            if bid <= 0 or ask < bid or timestamp < last_time:
                raise ValueError('Invalid or unsorted quote data')
            count += 1
            if count == 1:
                first_time = timestamp
            last_time, last_bid, last_ask = timestamp, bid, ask
            equity = balance + floating(bid, ask)
            peak = max(peak, equity)
            max_dd = max(max_dd, peak - equity)
            max_dd_pct = max(max_dd_pct, (peak - equity) / peak * 100)
            volume = sum(lots for _, lots, _ in positions)
            # Explicit conservative gross margin model; not broker-native hedged margin.
            margin = volume * contract * ask / leverage
            if margin > 0 and equity / margin * 100 <= 50:
                close(bid, ask, timestamp, 'simulated_stopout')
                stopouts += 1
                break
            if positions:
                net = floating(bid, ask) - commission * volume
                if len(positions) == 1:
                    direction, lots, price = positions[0]
                    hit = (bid - price if direction == 1 else price - ask) / point + 1e-7 >= 200 and net > 0
                else:
                    hit = net + 1e-8 >= 2 if mode == 'dollars' else net + 1e-8 >= 200 * base * contract * point
                if hit:
                    close(bid, ask, timestamp, 'target')
                    continue
                if len(positions) >= 5:
                    blocked = True
                direction, last_lot, _ = positions[-1]
                trigger = bid <= lower if direction == 1 else bid >= upper
                if blocked:
                    if not limit_noted:
                        limited_baskets += 1
                        limit_noted = True
                    continue
                if not trigger or (ask - bid) / point > 50:
                    continue
                direction = -direction
                lots = math.ceil(last_lot * multiplier / .01 - 1e-9) * .01
                if lots > 1 + 1e-9:
                    blocked = True
                    continue
            else:
                if (ask - bid) / point > 50:
                    continue
                rng ^= (rng << 13) & 0xffffffff
                rng ^= rng >> 17
                rng ^= (rng << 5) & 0xffffffff
                direction = 1 if rng & 1 == 0 else -1
                lots = base = .01
                start_time = timestamp
                upper = bid if direction == 1 else bid + 200 * point
                lower = upper - 200 * point
            next_margin = (volume + lots) * contract * ask / leverage
            after_fill_equity = equity - (ask - bid) * contract * lots - commission / 2 * lots
            if after_fill_equity < next_margin:
                margin_rejections += 1
                if positions:
                    blocked = True
                else:
                    # A start blocked by margin is an absorbing halt in this replay.
                    break
                continue
            positions.append((direction, lots, ask if direction == 1 else bid))
            balance -= commission / 2 * lots
            fill_equity = balance + floating(bid, ask)
            peak = max(peak, fill_equity)
            max_dd = max(max_dd, peak - fill_equity)
            max_dd_pct = max(max_dd_pct, (peak - fill_equity) / peak * 100)
            max_volume = max(max_volume, volume + lots)
            max_legs = max(max_legs, len(positions))
    end_open = len(positions)
    if positions:
        close(last_bid, last_ask, last_time, 'end_of_data')
    peak = max(peak, balance)
    max_dd = max(max_dd, peak - balance)
    max_dd_pct = max(max_dd_pct, (peak - balance) / peak * 100)
    wins = sum(c['net'] > 0 for c in cycles)
    gains = sum(max(c['net'], 0) for c in cycles)
    losses = -sum(min(c['net'], 0) for c in cycles)
    return {'engine': 'independent Python bid/ask replay; NOT native MT5',
            'data_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'ticks_processed': count, 'first_tick_msc': first_time, 'last_tick_msc': last_time,
            'multiplier': multiplier, 'target_mode': mode, 'seed': seed,
            'initial_deposit_usd': initial, 'ending_balance_usd': round(balance, 2),
            'net_profit_usd': round(balance - initial, 2),
            'maximum_equity_drawdown_usd': round(max_dd, 2),
            'maximum_equity_drawdown_percent': round(max_dd_pct, 2),
            'closed_baskets': len(cycles), 'winning_baskets': wins,
            'losing_baskets': sum(c['net'] < 0 for c in cycles),
            'profit_factor_by_basket': round(gains / losses, 4) if losses else None,
            'maximum_open_trades': max_legs, 'maximum_gross_lots': round(max_volume, 4),
            'baskets_reaching_trade_limit': limited_baskets,
            'margin_rejections': margin_rejections, 'simulated_stopouts': stopouts,
            'open_trades_forced_closed_at_end': end_open,
            'longest_closed_basket_hours': round(max((c['duration_seconds'] for c in cycles), default=0) / 3600, 2),
            'assumptions': {'commission_usd_per_lot_round_turn': commission, 'swap': 0,
                            'slippage': 0, 'execution_delay': 0, 'leverage': leverage,
                            'margin': 'gross notional / leverage (conservative approximation)',
                            'stopout': '50% margin level: liquidate entire simulated basket',
                            'end_of_data': 'liquidate remaining positions at final bid/ask',
                            'starting_lot': .01, 'max_trades': 5, 'max_lot': 1,
                            'grid_points': 200, 'initial_tp_points': 200,
                            'basket_dollars': 2, 'basket_equivalent_points': 200,
                            'max_spread_points': 50, 'point': point, 'contract_size': contract}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ticks', type=Path)
    parser.add_argument('--multiplier', type=float, default=2)
    parser.add_argument('--mode', choices=['dollars', 'points'], default='dollars')
    parser.add_argument('--seed', type=int, default=42)
    parser.add_argument('--commission', type=float, default=7)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.multiplier <= 1 or args.commission < 0 or not 0 < args.seed <= 0xffffffff:
        parser.error('Require multiplier > 1, commission >= 0, and nonzero uint32 seed')
    result = replay(args.ticks, args.multiplier, args.mode, args.seed, args.commission)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k not in ['assumptions', 'data_sha256']}))


if __name__ == '__main__':
    main()
