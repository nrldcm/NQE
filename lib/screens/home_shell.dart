// Bottom-navigation shell hosting the four main sections.
import 'package:flutter/material.dart';

import '../sim/ui/sandbox_screen.dart';
import '../theme.dart';
import 'books_screen.dart';
import 'dashboard_screen.dart';
import 'live_screen.dart';
import 'performance_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _tabs = [
    DashboardScreen(),
    BooksScreen(),
    LiveScreen(),
    SandboxScreen(),
    PerformanceScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Scaffold(
      backgroundColor: pal.bg,
      body: SafeArea(
        bottom: false,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: KeyedSubtree(
            key: ValueKey(_index),
            child: _tabs[_index],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: pal.isDark ? const Color(0xFF111111) : Colors.white,
          indicatorColor: pal.textHi.withOpacity(0.10),
          labelTextStyle: WidgetStateProperty.all(
            TextStyle(fontSize: 11, color: pal.textLo, fontWeight: FontWeight.w600),
          ),
        ),
        child: NavigationBar(
          height: 64,
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            _dest(Icons.dashboard_outlined, Icons.dashboard, 'Home', pal),
            _dest(Icons.account_balance_wallet_outlined,
                Icons.account_balance_wallet, 'Books', pal),
            _dest(Icons.candlestick_chart_outlined, Icons.candlestick_chart,
                'Live', pal),
            _dest(Icons.science_outlined, Icons.science, 'Trade', pal),
            _dest(Icons.calendar_month_outlined, Icons.calendar_month,
                'Performance', pal),
            _dest(Icons.settings_outlined, Icons.settings, 'Settings', pal),
          ],
        ),
      ),
    );
  }

  NavigationDestination _dest(
      IconData icon, IconData sel, String label, NqePalette pal) {
    return NavigationDestination(
      icon: Icon(icon, color: pal.textLo),
      selectedIcon: Icon(sel, color: pal.textHi),
      label: label,
    );
  }
}
