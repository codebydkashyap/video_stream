// lib/app.dart
import 'package:flutter/material.dart';
import 'features/host/host_dashboard_screen.dart';
import 'features/viewer/connection_screen.dart';

class DesktopSharingApp extends StatelessWidget {
  const DesktopSharingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Desktop Sharing',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const AppShell(),
      routes: {
        '/host': (_) => const HostDashboardScreen(),
        '/viewer': (_) => const ConnectionScreen(),
      },
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  static const _pages = [
    HostDashboardScreen(),
    ConnectionScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    if (isMobile) {
      // ── Mobile / Portrait: bottom navigation bar ──────────────────────────
      return Scaffold(
        backgroundColor: AppTheme.bg,
        body: SafeArea(child: _pages[_selectedIndex]),
        bottomNavigationBar: _BottomNav(
          selectedIndex: _selectedIndex,
          onTap: (i) => setState(() => _selectedIndex = i),
        ),
      );
    }

    // ── Tablet / Desktop: side navigation ────────────────────────────────────
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Row(
        children: [
          _SideNav(
            selectedIndex: _selectedIndex,
            onTap: (i) => setState(() => _selectedIndex = i),
          ),
          Expanded(child: _pages[_selectedIndex]),
        ],
      ),
    );
  }
}

// ── Bottom Navigation Bar (Mobile) ────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  const _BottomNav({required this.selectedIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _BottomNavItem(
                icon: Icons.cast_outlined,
                activeIcon: Icons.cast,
                label: 'Host',
                selected: selectedIndex == 0,
                onTap: () => onTap(0),
              ),
              _BottomNavItem(
                icon: Icons.desktop_windows_outlined,
                activeIcon: Icons.desktop_windows,
                label: 'Viewer',
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

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _BottomNavItem({
    required this.icon,
    required this.activeIcon,
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
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color:
              selected ? AppTheme.accent.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? activeIcon : icon,
              size: 22,
              color: selected ? AppTheme.accent : AppTheme.textMuted,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: selected ? AppTheme.accent : AppTheme.textMuted,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Side Navigation (Tablet / Desktop) ────────────────────────────────────────

class _SideNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  const _SideNav({required this.selectedIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      color: AppTheme.surface,
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 40),
            _logo(),
            const SizedBox(height: 36),
            _NavItem(
              icon: Icons.cast_outlined,
              label: 'Host',
              selected: selectedIndex == 0,
              onTap: () => onTap(0),
            ),
            _NavItem(
              icon: Icons.desktop_windows_outlined,
              label: 'Viewer',
              selected: selectedIndex == 1,
              onTap: () => onTap(1),
            ),
            const SizedBox(height: 100), // Safety spacer instead of Spacer()
            _buildVersion(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _logo() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.accent, AppTheme.accentAlt],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.screen_share_outlined,
              color: Colors.white, size: 20),
        ),
        const SizedBox(width: 10),
        const Text(
          'DK MEET',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildVersion() {
    return const Text(
      'v1.0.0',
      style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color:
              selected ? AppTheme.accent.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: selected
              ? Border.all(color: AppTheme.accent.withOpacity(0.4))
              : Border.all(color: Colors.transparent),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? AppTheme.accent : AppTheme.textMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : AppTheme.textMuted,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppTheme {
  static const bg = Color(0xFF0D1117);
  static const surface = Color(0xFF161B22);
  static const surfaceAlt = Color(0xFF21262D);
  static const accent = Color(0xFF58A6FF);
  static const accentAlt = Color(0xFF1F6FEB);
  static const success = Color(0xFF3FB950);
  static const danger = Color(0xFFF85149);
  static const warning = Color(0xFFD29922);
  static const textMuted = Color(0xFF8B949E);

  static final dark = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    fontFamily: 'Inter',
    colorScheme: ColorScheme.dark(
      primary: accent,
      secondary: accentAlt,
      surface: surface,
      error: danger,
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Colors.white, fontSize: 14),
      bodyMedium: TextStyle(color: Colors.white70, fontSize: 13),
      titleLarge: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: 22,
      ),
    ),
  );
}
