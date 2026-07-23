// In-app trade notifications for the Sandbox: a bell with an unread badge, a
// history sheet, and a helper to flash a transient banner when a new notice
// (fill, stop-loss / take-profit hit, liquidation) arrives.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme.dart';
import '../sim_state.dart';

IconData noticeIcon(SimNoticeType t) => switch (t) {
      SimNoticeType.filled => Icons.check_circle_outline,
      SimNoticeType.stopHit => Icons.trending_down,
      SimNoticeType.tpHit => Icons.trending_up,
      SimNoticeType.liquidation => Icons.warning_amber_rounded,
      SimNoticeType.info => Icons.info_outline,
    };

Color noticeColor(SimNoticeType t) => switch (t) {
      SimNoticeType.filled => const Color(0xFF4C8DFF),
      SimNoticeType.stopHit => NqeColors.loss,
      SimNoticeType.tpHit => NqeColors.gain,
      SimNoticeType.liquidation => NqeColors.loss,
      SimNoticeType.info => const Color(0xFF9A9A9A),
    };

/// Bell icon with an unread badge; opens the notifications history.
class SandboxNoticesButton extends StatelessWidget {
  const SandboxNoticesButton({super.key});

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return ListenableBuilder(
      listenable: simState,
      builder: (context, _) {
        final count = simState.notices.length;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: Icon(Icons.notifications_outlined, color: pal.textHi),
              tooltip: 'Notifications',
              onPressed: () => showSandboxNotices(context),
            ),
            if (count > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                      color: NqeColors.loss, shape: BoxShape.circle),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

Future<void> showSandboxNotices(BuildContext context) {
  final pal = context.nqe;
  return showModalBottomSheet(
    context: context,
    backgroundColor: pal.bg,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, scroll) => ListenableBuilder(
        listenable: simState,
        builder: (context, _) {
          final notices = simState.notices;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
                child: Row(
                  children: [
                    Text('Notifications',
                        style: TextStyle(
                            color: pal.textHi,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    const Spacer(),
                    if (notices.isNotEmpty)
                      TextButton(
                        onPressed: simState.clearNotices,
                        child: const Text('Clear all'),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: notices.isEmpty
                    ? Center(
                        child: Text('No notifications yet.',
                            style: TextStyle(color: pal.textLo)),
                      )
                    : ListView.builder(
                        controller: scroll,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: notices.length,
                        itemBuilder: (context, i) {
                          final n = notices[i];
                          final c = noticeColor(n.type);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: pal.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: pal.line),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(noticeIcon(n.type), color: c, size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(n.title,
                                            style: TextStyle(
                                                color: pal.textHi,
                                                fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 2),
                                        Text(n.message,
                                            style: TextStyle(
                                                color: pal.textLo,
                                                fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  if (n.tsMs > 0)
                                    Text(
                                      DateFormat('HH:mm').format(
                                          DateTime.fromMillisecondsSinceEpoch(
                                              n.tsMs)),
                                      style: TextStyle(
                                          color: pal.textLo, fontSize: 10),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
