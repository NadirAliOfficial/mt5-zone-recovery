"""Economic fixtures verify replay fills, costs, and unresolved exposure."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
spec = importlib.util.spec_from_file_location('replay', Path(__file__).parents[1] / 'tools/replay.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class ReplayTests(unittest.TestCase):
    def run_quotes(self, quotes, **options):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'ticks.csv'
            path.write_text('time_msc,bid,ask\n' + '\n'.join(
                f'{1000 + i * 1000},{bid:.5f},{ask:.5f}' for i, (bid, ask) in enumerate(quotes)))
            return module.replay(path, **options)

    def test_initial_tp_uses_executable_bid(self):
        r = self.run_quotes([(1.1, 1.1001), (1.1021, 1.1022)], commission=0)
        self.assertEqual(r['net_profit_usd'], 2)
        self.assertEqual(r['closed_baskets'], 1)
        self.assertEqual(r['open_trades_forced_closed_at_end'], 0)
        self.assertAlmostEqual(r['maximum_equity_drawdown_usd'], .1)

    def test_recovery_pays_original_loss_and_spread(self):
        r = self.run_quotes([(1.1,1.1001), (1.098,1.0981),
                             (1.0938,1.0939), (1.0936,1.0937)], commission=0)
        self.assertEqual(r['net_profit_usd'], 2.1)
        self.assertEqual(r['maximum_open_trades'], 2)
        self.assertEqual(r['open_trades_forced_closed_at_end'], 0)

    def test_round_turn_cost_delays_exit(self):
        r = self.run_quotes([(1.1,1.1001), (1.098,1.0981),
                             (1.0936,1.0937), (1.0934,1.0935)], commission=7)
        self.assertEqual(r['net_profit_usd'], 2.09)
        self.assertEqual(r['open_trades_forced_closed_at_end'], 0)

    def test_unresolved_loss_not_hidden(self):
        r = self.run_quotes([(1.1,1.1001), (1.099,1.0991)], commission=0)
        self.assertEqual(r['net_profit_usd'], -1.1)
        self.assertEqual(r['open_trades_forced_closed_at_end'], 1)
        self.assertEqual(r['losing_baskets'], 1)

    def test_fixed_points_equivalent_to_dollars_at_base_lot(self):
        quotes=[(1.1,1.1001),(1.098,1.0981),(1.0934,1.0935)]
        a=self.run_quotes(quotes, mode='dollars')
        b=self.run_quotes(quotes, mode='points')
        self.assertEqual(a['ending_balance_usd'], b['ending_balance_usd'])

    def test_trade_cap_stops_additions(self):
        quotes=[(1.1,1.1001),(1.098,1.0981),(1.1,1.1001),
                (1.098,1.0981),(1.1,1.1001),(1.098,1.0981)]
        r=self.run_quotes(quotes, commission=0)
        self.assertEqual(r['maximum_open_trades'],5)
        self.assertEqual(r['baskets_reaching_trade_limit'],1)
        self.assertEqual(r['open_trades_forced_closed_at_end'],5)

if __name__ == '__main__':
    unittest.main()
