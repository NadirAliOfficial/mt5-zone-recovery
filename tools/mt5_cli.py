#!/usr/bin/env python3
"""Compile and backtest in a user-supplied, isolated MT5 portable installation."""
import argparse
import configparser
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

REPO = Path(__file__).resolve().parents[1]


def run():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--terminal', type=Path, required=True)
    parser.add_argument('--wine', type=Path, help='Wine executable, omit on Windows')
    parser.add_argument('--wine-prefix', type=Path)
    parser.add_argument('--timeout', type=int, default=900)
    sub = parser.add_subparsers(dest='action', required=True)
    sub.add_parser('compile')
    test = sub.add_parser('test')
    test.add_argument('config', type=Path)
    test.add_argument('--login', type=int, help='Existing saved demo account ID; never committed')
    export = sub.add_parser('export')
    export.add_argument('--login', type=int, required=True, help='Saved demo login, stored only in temporary terminal config')
    args = parser.parse_args()
    terminal = args.terminal.resolve()
    env = os.environ.copy()
    if args.wine_prefix:
        env['WINEPREFIX'] = str(args.wine_prefix.resolve())
    env.update(WINEDEBUG='-all', MVK_CONFIG_LOG_LEVEL='0',
               WINEDLLOVERRIDES='winemenubuilder.exe=d')

    def windows(path):
        return 'Z:' + str(path).replace('/', '\\') if args.wine else str(path)

    def launch(exe, *parameters):
        command = ([str(args.wine)] if args.wine else []) + [str(terminal / exe), *parameters]
        # Wine launcher exit codes do not reliably indicate compile/test success.
        return subprocess.run(command, env=env, stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL, timeout=args.timeout)

    if args.action == 'compile':
        shutil.copytree(REPO / 'MQL5', terminal / 'MQL5', dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns('*.ex5'))
        log = terminal / 'aziz-compile.log'
        log.unlink(missing_ok=True)
        source = terminal / 'MQL5/Experts/AzizZoneRecovery/AzizZoneRecovery.mq5'
        launch('MetaEditor64.exe', '/portable', '/compile:' + windows(source),
               '/log:' + windows(log))
        text = log.read_text(encoding='utf-16') if log.exists() else ''
        result = re.search(r'Result: ([^\r\n]+)', text)
        print(result.group(0) if result else 'Compiler did not produce a result')
        if '0 errors, 0 warnings' not in text:
            sys.exit(1)
        shutil.copy2(source.with_suffix('.ex5'),
                     REPO / 'MQL5/Experts/AzizZoneRecovery/AzizZoneRecovery.ex5')
    elif args.action == 'export':
        source = terminal / 'MQL5/Scripts/ExportAzizTicks.mq5'
        source.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(REPO / 'MQL5/Scripts/ExportAzizTicks.mq5', source)
        log = terminal / 'aziz-export-compile.log'
        log.unlink(missing_ok=True)
        launch('MetaEditor64.exe', '/portable', '/compile:' + windows(source),
               '/log:' + windows(log))
        text = log.read_text(encoding='utf-16') if log.exists() else ''
        if '0 errors, 0 warnings' not in text:
            sys.exit('Exporter compilation failed; inspect aziz-export-compile.log')
        config = configparser.ConfigParser(interpolation=None)
        config.optionxform = str
        config['Common'] = {'Server': 'MetaQuotes-Demo', 'Login': str(args.login), 'KeepPrivate': '0'}
        config['Experts'] = {'AllowLiveTrading': '0', 'AllowDllImport': '0', 'Enabled': '1'}
        config['StartUp'] = {'Script': 'ExportAzizTicks', 'Symbol': 'EURUSD',
                             'Period': 'M1', 'ShutdownTerminal': '1'}
        private_config = terminal / 'aziz-run.ini'
        with private_config.open('w') as handle:
            config.write(handle, space_around_delimiters=False)
        private_config.chmod(0o600)
        ticks = terminal / 'MQL5/Files/aziz-eurusd-ticks.csv'
        ticks.unlink(missing_ok=True)
        try:
            launch('terminal64.exe', '/portable', '/config:' + windows(private_config))
        finally:
            private_config.unlink(missing_ok=True)
        if not ticks.exists() or ticks.stat().st_size < 100:
            sys.exit('No tick data exported. Inspect the MQL5 script journal.')
        print('Historical tick CSV (verify EXPORT_OK in script journal):', ticks)
    else:
        config = configparser.ConfigParser(interpolation=None)
        config.optionxform = str
        config.read(args.config)
        config['Experts'] = {'AllowLiveTrading': '0', 'AllowDllImport': '0', 'Enabled': '1'}
        for option in ['UseRemote', 'UseCloud', 'Visual', 'Optimization']:
            config['Tester'][option] = '0'
        config['Tester']['ShutdownTerminal'] = '1'
        config['Tester']['ReplaceReport'] = '1'
        if args.login:
            config['Common']['Login'] = str(args.login)
        if config.has_section('TesterInputs'):
            preset_name = 'aziz-' + args.config.stem + '.set'
            preset = terminal / 'MQL5/Profiles/Tester' / preset_name
            preset.parent.mkdir(parents=True, exist_ok=True)
            preset.write_text(''.join(key + '=' + value + '\n'
                                      for key, value in config['TesterInputs'].items()))
            config['Tester']['ExpertParameters'] = preset_name
            config.remove_section('TesterInputs')
        relative = Path(config['Tester']['Report'].replace('\\', '/'))
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError('Report must be relative to portable terminal')
        report = terminal / relative
        report.parent.mkdir(parents=True, exist_ok=True)
        report.unlink(missing_ok=True)
        private_config = terminal / 'aziz-run.ini'
        with private_config.open('w') as handle:
            config.write(handle, space_around_delimiters=False)
        private_config.chmod(0o600)
        try:
            launch('terminal64.exe', '/portable', '/config:' + windows(private_config))
        finally:
            private_config.unlink(missing_ok=True)
        if not report.exists():
            sys.exit('No native report produced. Inspect terminal and tester logs.')
        for file in report.parent.glob(report.stem + '*'):
            shutil.copy2(file, REPO / 'reports' / file.name)
        print('Native MT5 report:', REPO / 'reports' / report.name)


if __name__ == '__main__':
    run()
