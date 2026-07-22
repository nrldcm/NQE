// Compact, theme-aware glyph + label reflecting the desktop [SyncClient]'s
// live [SyncConn]. A pure StatelessWidget — the owner passes the current state
// (and, while reconnecting, the attempt number) so it can live anywhere from a
// top-bar chip to the big status readout on the sync panel.
import 'package:flutter/material.dart';

import '../sync/sync_client.dart';
import '../theme.dart';

class ConnectionWatcher extends StatelessWidget {
  final SyncConn state;

  /// Retry counter, shown while [SyncConn.reconnecting]. Optional.
  final int attempt;

  const ConnectionWatcher(this.state, {this.attempt = 0, super.key});

  static const _amber = Color(0xFFE3B341);

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;

    final (Color color, IconData icon, String label, bool busy) =
        switch (state) {
      SyncConn.idle => (pal.textLo, Icons.circle_outlined, 'Not connected', false),
      SyncConn.connecting => (_amber, Icons.sync, 'Connecting…', true),
      SyncConn.reconnecting => (
          _amber,
          Icons.sync,
          attempt > 0 ? 'Reconnecting… (attempt $attempt)' : 'Reconnecting…',
          true,
        ),
      SyncConn.connected =>
        (NqeColors.gain, Icons.check_circle, 'Connected', false),
      SyncConn.disconnected =>
        (NqeColors.loss, Icons.error, 'Disconnected', false),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            )
          else
            Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
