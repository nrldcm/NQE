// Compact, theme-aware banner that reflects the live [PeerState] of the LAN
// sync link (idle / (re)connecting / connected / disconnected).
import 'package:flutter/material.dart';

import '../sync/sync_server.dart';
import '../theme.dart';

class ConnectionStatusBanner extends StatelessWidget {
  final PeerState state;
  const ConnectionStatusBanner(this.state, {super.key});

  static const _amber = Color(0xFFE3B341);

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;

    final (Color color, IconData icon, String label, bool busy) =
        switch (state) {
      PeerState.idle => (pal.textLo, Icons.podcasts_outlined,
          'Waiting for desktop', false),
      PeerState.connecting ||
      PeerState.reconnecting =>
        (_amber, Icons.sync, 'Reconnecting…', true),
      PeerState.connected => (
          NqeColors.gain,
          Icons.check_circle_outline,
          'Connected',
          false
        ),
      PeerState.disconnected => (
          NqeColors.loss,
          Icons.link_off,
          'Disconnected',
          false
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          if (busy)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            )
          else
            Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
