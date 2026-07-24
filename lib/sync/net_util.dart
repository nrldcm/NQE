// Networking helpers for the LAN sync/pairing servers.
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Bind a shelf handler on 0.0.0.0, preferring [preferred] but scanning upward
/// through [span] ports if it is busy/blocked — a lightweight "find an open
/// port" so a firewalled or in-use port doesn't break pairing. Falls back to an
/// OS-assigned ephemeral port (0) as a last resort. Read `server.port` for the
/// port actually bound (that is what gets advertised in the QR / pairing).
Future<HttpServer> bindWithFallback(
  Handler handler,
  int preferred, {
  int span = 40,
  SecurityContext? securityContext,
}) async {
  Object? lastErr;
  for (var p = preferred; p <= preferred + span; p++) {
    if (p < 1 || p > 65535) continue;
    try {
      return await shelf_io.serve(handler, '0.0.0.0', p,
          securityContext: securityContext);
    } catch (e) {
      lastErr = e; // in use / not permitted — try the next port
    }
  }
  // Last resort: let the OS pick any free port.
  try {
    return await shelf_io.serve(handler, '0.0.0.0', 0,
        securityContext: securityContext);
  } catch (e) {
    lastErr = e;
  }
  throw StateError('No bindable port near $preferred: $lastErr');
}

/// Clamp a user-entered port into the usable, non-privileged range.
int sanitizePort(int p, {int fallback = 8787}) {
  if (p < 1024 || p > 65535) return fallback;
  return p;
}

/// Heuristic: is this network-interface name a virtual/VPN/container adapter
/// whose address a phone on the real Wi-Fi can't reach? Used to skip them when
/// picking a LAN address / scanning subnets.
bool isVirtualAdapter(String name) {
  final n = name.toLowerCase();
  const bad = [
    'vethernet', 'vmware', 'virtualbox', 'vbox', 'hyper-v', 'hyperv',
    'wsl', 'docker', 'loopback', 'tailscale', 'zerotier', 'tunnel',
    'tap', 'tun', 'bluetooth', 'vpn', 'radmin', 'hamachi', 'npcap',
  ];
  for (final b in bad) {
    if (n.contains(b)) return true;
  }
  return false;
}
