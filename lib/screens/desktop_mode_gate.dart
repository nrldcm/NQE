// Full-screen lock shown on the PHONE while a desktop is connected in
// "Desktop Mode". The phone stays the source of truth and its engine keeps
// running/syncing in the background, but the human is locked out here so only
// one device is ever driven at a time — no double edits, no sync conflicts.
// Tapping Disconnect stops the server, dropping the desktop and freeing the
// phone for use again.
import 'package:flutter/material.dart';

import '../sync/sync_server.dart';
import '../theme.dart';

class DesktopModeGate extends StatelessWidget {
  const DesktopModeGate({super.key});

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Material(
      color: pal.bg,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: pal.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: pal.line),
                    ),
                    child: Icon(Icons.desktop_windows_outlined,
                        size: 42, color: pal.textHi),
                  ),
                  const SizedBox(height: 22),
                  Text('Desktop Mode',
                      style: TextStyle(
                          color: pal.textHi,
                          fontSize: 24,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Text(
                    'Your desktop is connected and in control. This phone stays '
                    'the source of truth and keeps syncing in the background — '
                    'activity here is paused so the two devices never conflict.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: pal.textLo, fontSize: 14, height: 1.4),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => SyncServer.instance.stop(),
                      icon: const Icon(Icons.link_off),
                      label: const Text('Disconnect desktop'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        textStyle: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text('Disconnecting frees this phone for trading again.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: pal.textLo, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
