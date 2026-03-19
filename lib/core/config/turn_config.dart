// lib/core/config/turn_config.dart
//
// ─────────────────────────────────────────────────────────────────────────────
//  METERED TURN SERVER CREDENTIALS
//  Get these from: https://dashboard.metered.ca/turnserver
//  → Select your project → Copy the credentials shown below
// ─────────────────────────────────────────────────────────────────────────────

class TurnConfig {
  TurnConfig._();

  // ── Your Metered TURN credentials (from dashboard.metered.ca/turnserver) ──
  static const String username = '67407e97cd548831c5e95850';
  static const String credential = 'zU+hO+36A4r8mfjY';

  // ─────────────────────────────────────────────────────────────────────────
  // The TURN server URLs — these are standard for Metered, do NOT change them
  // unless your Metered dashboard shows different URLs.
  // ─────────────────────────────────────────────────────────────────────────
  static List<Map<String, dynamic>> get iceServers => [
        // ── STUN (tried first, free, no credentials needed) ────────────────
        {'urls': 'stun:stun.metered.ca:80'},
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},

        // ── Metered STUN relay ──────────────────────────────────────────────
        {'urls': 'stun:stun.relay.metered.ca:80'},

        // ── TURN over UDP port 80 (fast relay) ─────────────────────────────
        {
          'urls': 'turn:global.relay.metered.ca:80',
          'username': username,
          'credential': credential
        },

        // ── TURN over TCP port 80 (NAT fallback) ───────────────────────────
        {
          'urls': 'turn:global.relay.metered.ca:80?transport=tcp',
          'username': username,
          'credential': credential
        },

        // ── TURN over UDP port 443 ─────────────────────────────────────────
        {
          'urls': 'turn:global.relay.metered.ca:443',
          'username': username,
          'credential': credential
        },

        // ── TURNS over TLS port 443 (most firewall-friendly) ───────────────
        {
          'urls': 'turns:global.relay.metered.ca:443?transport=tcp',
          'username': username,
          'credential': credential
        },
      ];

  // STUN-only list (used first; if ICE fails, full list above is used)
  static List<Map<String, dynamic>> get stunOnlyServers => [
        {'urls': 'stun:stun.metered.ca:80'},
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ];
}
