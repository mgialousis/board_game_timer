import 'package:flutter/material.dart';

import 'controllers/game_controller.dart';
import 'screens/game_screen.dart';
import 'screens/setup_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(TurnTimerApp(controller: GameController()));
}

class TurnTimerApp extends StatefulWidget {
  const TurnTimerApp({super.key, required this.controller});

  final GameController controller;

  @override
  State<TurnTimerApp> createState() => _TurnTimerAppState();
}

class _TurnTimerAppState extends State<TurnTimerApp> {
  late final Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    // The controller observes app lifecycle to persist state and manage the
    // wakelock when the app is backgrounded/resumed.
    WidgetsBinding.instance.addObserver(widget.controller);
    _initFuture = widget.controller.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(widget.controller);
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TurnTimer',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          // Resume a game in progress, otherwise start at setup.
          return widget.controller.hasActiveGame
              ? GameScreen(controller: widget.controller)
              : SetupScreen(controller: widget.controller);
        },
      ),
    );
  }
}
