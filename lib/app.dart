// lib/app.dart
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'features/host/host_dashboard_screen.dart';
import 'features/viewer/connection_screen.dart';

class DesktopSharingApp extends StatelessWidget {
  const DesktopSharingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DK Meet',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const AppShell(),
      onGenerateRoute: (settings) {
        final name = settings.name ?? '';
        final uri = Uri.tryParse(name);

        if (uri != null && (uri.path == '/join' || name.contains('/join'))) {
          final device = uri.queryParameters['device'];
          final code = uri.queryParameters['code'];
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => ConnectionScreen(
              prefilledDeviceId: device,
              prefilledCode: code,
            ),
          );
        }

        switch (name) {
          case '/host':
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => const HostDashboardScreen(),
            );
          case '/viewer':
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => const ConnectionScreen(),
            );
        }
        return null;
      },
    );
  }
}

// ── App Shell ─────────────────────────────────────────────────────────────────

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  late final AnimationController _bgAnim;

  static const _pages = [HostDashboardScreen(), ConnectionScreen()];

  @override
  void initState() {
    super.initState();
    _bgAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
    _listenDeepLinks();
  }

  @override
  void dispose() {
    _bgAnim.dispose();
    super.dispose();
  }

  void _listenDeepLinks() {
    if (kIsWeb) return;
    try {
      AppLinks().uriLinkStream.listen((uri) {
        if (!mounted) return;
        final device = uri.queryParameters['device'];
        final code = uri.queryParameters['code'];
        if ((uri.path.endsWith('/join') || uri.fragment.contains('/join')) &&
            device != null &&
            code != null) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ConnectionScreen(
              prefilledDeviceId: device,
              prefilledCode: code,
            ),
          ));
        }
      });
    } catch (e) {
      debugPrint('[DeepLink] app_links init error (non-fatal): $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Stack(
        children: [
          // Holographic Dot Grid Background
          AnimatedBuilder(
            animation: _bgAnim,
            builder: (context, child) {
              return CustomPaint(
                painter: _DotGridPainter(animationValue: _bgAnim.value),
                size: Size.infinite,
              );
            },
          ),

          // Main Content
          Positioned.fill(
            bottom: 80, // Leave space for dock
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _pages[_selectedIndex],
            ),
          ),

          // Floating Dock Navigation
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: _FloatingDock(
                selectedIndex: _selectedIndex,
                onTap: (i) => setState(() => _selectedIndex = i),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Holographic Dot Grid Painter ──────────────────────────────────────────────

class _DotGridPainter extends CustomPainter {
  final double animationValue;

  _DotGridPainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1A2332)
      ..style = PaintingStyle.fill;

    const double spacing = 30.0;
    final int cols = (size.width / spacing).ceil();
    final int rows = (size.height / spacing).ceil();

    for (int i = 0; i <= cols; i++) {
      for (int j = 0; j <= rows; j++) {
        final x = i * spacing;
        final y = j * spacing;
        
        // Create a wave effect based on position and time
        final distance = math.sqrt(math.pow(x - size.width / 2, 2) + math.pow(y - size.height / 2, 2));
        final phase = distance / 100.0 - animationValue * math.pi * 4;
        final opacity = (math.sin(phase) + 1) / 2; // 0.0 to 1.0

        final radius = 1.0 + (opacity * 1.5);
        
        paint.color = Color(0xFF1A2332).withValues(alpha: 0.3 + (opacity * 0.7));
        
        // Add subtle electric blue glow to some dots
        if (opacity > 0.9 && i % 3 == 0 && j % 3 == 0) {
           paint.color = AppTheme.electricBlue.withValues(alpha: 0.8);
           canvas.drawCircle(Offset(x, y), radius * 1.2, paint);
        } else {
           canvas.drawCircle(Offset(x, y), radius, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotGridPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}

// ── Floating Dock Navigation ──────────────────────────────────────────────────

class _FloatingDock extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  
  const _FloatingDock({required this.selectedIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.surfaceGlass.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DockItem(
                icon: Icons.cast_rounded,
                label: 'Host',
                selected: selectedIndex == 0,
                onTap: () => onTap(0),
              ),
              const SizedBox(width: 8),
              _DockItem(
                icon: Icons.desktop_windows_rounded,
                label: 'Join',
                selected: selectedIndex == 1,
                onTap: () => onTap(1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DockItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? Colors.white.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? Colors.white.withValues(alpha: 0.2) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? Colors.white : AppTheme.textMuted,
            ),
            if (selected) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}

// ── Theme ─────────────────────────────────────────────────────────────────────

class AppTheme {
  // Ultra-premium holographic command center colors
  static const bg = Color(0xFF060A13); // Deep space black
  static const surfaceGlass = Color(0xFF101623); // Slightly lighter for glass
  
  static const electricBlue = Color(0xFF00B4D8);
  static const violet = Color(0xFF8B5CF6);
  static const pink = Color(0xFFEC4899);
  static const neonGreen = Color(0xFF10B981);
  
  // Backward compatibility / semantic mapping
  static const cyan = electricBlue;
  static const purple = violet;
  static const danger = Color(0xFFF43F5E); // Rose
  static const success = neonGreen;
  static const warning = Color(0xFFF59E0B);
  static const textMuted = Color(0xFF64748B);
  
  // Common Gradients
  static const primaryGradient = LinearGradient(
    colors: [electricBlue, violet],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const connectGradient = LinearGradient(
    colors: [electricBlue, violet, pink],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static final dark = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Colors.transparent, // Scaffold relies on AppShell bg
    fontFamily: 'Inter',
    colorScheme: ColorScheme.dark(
      primary: electricBlue,
      secondary: violet,
      surface: bg,
      error: danger,
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Colors.white, fontSize: 14),
      bodyMedium: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
      titleLarge: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: 22,
      ),
    ),
  );
}

// ── Reusable Holographic Card ─────────────────────────────────────────────────

class HoloCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  
  const HoloCard({
    super.key,
    required this.child,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceGlass.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          padding: padding ?? const EdgeInsets.all(24),
          child: child,
        ),
      ),
    );
  }
}
