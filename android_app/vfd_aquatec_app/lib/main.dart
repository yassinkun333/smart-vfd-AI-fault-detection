import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/vfd_provider.dart';
import 'theme/app_theme.dart';
import 'screens/dashboard_screen.dart';
import 'screens/control_screen.dart';
import 'screens/charts_screen.dart';
import 'screens/console_screen.dart';
import 'screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Status bar style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  // Request BLE permissions
  await [
    Permission.bluetooth,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.locationWhenInUse,
  ].request();

  runApp(
    ChangeNotifierProvider(
      create: (_) => VfdProvider(),
      child: const VfdApp(),
    ),
  );
}

class VfdApp extends StatelessWidget {
  const VfdApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VFD-Aquatec',
      theme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _page = 0;

  static const _pages = [
    DashboardScreen(),
    ControlScreen(),
    ChartsScreen(),
    ConsoleScreen(),
    SettingsScreen(),
  ];

  static const _labels = [
    'Tableau de bord',
    'Contrôle',
    'Graphes',
    'Console',
    'Réglages',
  ];

  static const _icons = [
    Icons.dashboard_rounded,
    Icons.tune_rounded,
    Icons.show_chart_rounded,
    Icons.terminal_rounded,
    Icons.settings_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final vfd = context.watch<VfdProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8, height: 8,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: vfd.simMode
                  ? AppTheme.warning
                  : vfd.bleConnected
                    ? AppTheme.running
                    : AppTheme.stopped,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(
                  color: (vfd.simMode
                    ? AppTheme.warning
                    : vfd.bleConnected
                      ? AppTheme.running
                      : AppTheme.stopped).withOpacity(0.7),
                  blurRadius: 6, spreadRadius: 1,
                )],
              ),
            ),
            const Text('VFD-Aquatec'),
          ],
        ),
        actions: [
          // Sim badge
          if (vfd.simMode)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.warning.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.warning.withOpacity(0.5)),
              ),
              child: const Text('SIM',
                style: TextStyle(color: AppTheme.warning,
                  fontSize: 11, fontWeight: FontWeight.w800)),
            ),
          // BLE indicator
          if (!vfd.simMode)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: IconButton(
                icon: Icon(
                  vfd.bleConnected
                    ? Icons.bluetooth_connected
                    : Icons.bluetooth_disabled,
                  color: vfd.bleConnected ? AppTheme.running : AppTheme.stopped,
                ),
                onPressed: vfd.bleConnected ? null : vfd.startScan,
                tooltip: vfd.bleStatus,
              ),
            ),
        ],
      ),
      body: IndexedStack(
        index: _page,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppTheme.surface,
        indicatorColor: AppTheme.primary.withOpacity(0.2),
        selectedIndex: _page,
        onDestinationSelected: (i) => setState(() => _page = i),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: List.generate(_pages.length, (i) => NavigationDestination(
          icon:         Icon(_icons[i], color: AppTheme.textMuted),
          selectedIcon: Icon(_icons[i], color: AppTheme.primary),
          label: _labels[i],
        )),
      ),
    );
  }
}
