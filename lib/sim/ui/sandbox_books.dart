// A view-only "Sandbox" book for the Home → Books list: the simulation's
// Overview + Trade History, no trading controls. Trading itself lives on the
// Sandbox (Trade) tab; here you just review it.
import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/common.dart';
import '../sim_state.dart';
import 'sandbox_analytics_panel.dart';
import 'sandbox_common.dart';

/// A Books-list tile that opens the read-only sandbox overview.
class SandboxBooksTile extends StatelessWidget {
  const SandboxBooksTile({super.key});

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    simState.init(); // ensure it's loaded even if the Trade tab wasn't opened
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: pal.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SandboxBooksPage()),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: pal.line),
            ),
            child: ListenableBuilder(
              listenable: simState,
              builder: (context, _) {
                final equity = simState.equity;
                final ret = () {
                  final start = simState.account?.startingCash ?? 0;
                  return start == 0 ? 0.0 : (equity - start) / start * 100;
                }();
                return Row(
                  children: [
                    Icon(Icons.science_outlined, size: 20, color: pal.textHi),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('Sandbox',
                                  style: TextStyle(
                                      color: pal.textHi,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(width: 8),
                              Pill('Simulation', color: pal.textLo),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text('Paper trading · view only',
                              style: TextStyle(color: pal.textLo, fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            simMoney(equity, currency: simState.currency),
                            maxLines: 1,
                            style: TextStyle(
                                color: pal.textHi,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3),
                          ),
                        ),
                        const SizedBox(height: 2),
                        PnlText(ret, signedPctStr(ret), size: 12),
                      ],
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, size: 20, color: pal.textLo),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen, read-only overview + trade history for the sandbox.
class SandboxBooksPage extends StatefulWidget {
  const SandboxBooksPage({super.key});

  @override
  State<SandboxBooksPage> createState() => _SandboxBooksPageState();
}

class _SandboxBooksPageState extends State<SandboxBooksPage> {
  @override
  void initState() {
    super.initState();
    simState.init();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(title: const Text('Sandbox · Simulation')),
      body: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: SandboxAnalyticsPanel(),
      ),
    );
  }
}
