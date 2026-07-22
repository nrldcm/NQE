// About / credits.
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/nqe_logo.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        children: [
          const SizedBox(height: 20),
          const Center(child: NqeLogo(scale: 0.9)),
          const SizedBox(height: 24),
          const Center(child: WillongByline()),
          const SizedBox(height: 40),
          _card(pal, [
            _row(pal, 'For', 'John Rey Tampus'),
            _divider(pal),
            _row(pal, 'Fund', 'Willong Capital'),
            _divider(pal),
            _row(pal, 'Developed by', 'Norell Mantilla'),
            _divider(pal),
            _row(pal, 'Version', '1.0.0'),
          ]),
          const SizedBox(height: 24),
          Text(
            'NQE is a private, offline-first trading ledger. Your data is stored '
            'securely on this device in an encrypted-capable SQLite database and '
            'never leaves your phone unless you export an encrypted backup.',
            style: TextStyle(color: pal.textLo, fontSize: 13, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          Center(
            child: Text(
              '© ${DateTime.now().year} Willong Capital · NQE',
              style: TextStyle(color: pal.textLo, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(NqePalette pal, List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: pal.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: pal.line),
        ),
        child: Column(children: children),
      );

  Widget _row(NqePalette pal, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: TextStyle(color: pal.textLo, fontSize: 14)),
            Text(v,
                style: TextStyle(
                    color: pal.textHi,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _divider(NqePalette pal) =>
      Divider(height: 1, color: pal.line, indent: 18, endIndent: 18);
}
