import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/perf.dart';
import 'globals.dart';
import 'models/track.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/player_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/search_screen.dart';
import 'splash/glass_splash.dart';
import 'theme/app_theme.dart';
import 'widgets/liquid_nav.dart';
import 'widgets/mini_player.dart';

class SoundXsApp extends StatelessWidget {
  const SoundXsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SoundXs',
      theme: buildTheme(),
      home: GlassSplash(next: () => const MainShell()),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;
  bool _shrunk = false;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    // Halaman dibuat SEKALI. Instance yang sama dipakai ulang.
    _pages = [
      HomeScreen(onPlay: _onPlay),
      SearchScreen(onPlay: _onPlay),
      LibraryScreen(onPlay: _onPlay),
      const ProfileScreen(),
    ];
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
    ));
    audioHandler.errorMessage.addListener(_onError);
  }

  @override
  void dispose() {
    audioHandler.errorMessage.removeListener(_onError);
    super.dispose();
  }

  void _onError() {
    final msg = audioHandler.errorMessage.value;
    if (msg == null || !mounted) return;
    audioHandler.errorMessage.value = null;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  void _setShrunk(bool v) {
    if (_shrunk == v || !mounted) return;
    setState(() => _shrunk = v);
  }

  /// Scroll ke bawah -> navigasi menyusut jadi bulet. Scroll ke atas / paling atas -> membesar lagi.
  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is ScrollUpdateNotification) {
      final d = n.scrollDelta ?? 0;
      if (n.metrics.pixels <= 4) {
        _setShrunk(false);
      } else if (d > 4) {
        _setShrunk(true);
      } else if (d < -4) {
        _setShrunk(false);
      }
    }
    return false;
  }

  void _select(int i) {
    if (_tab == i) return;
    setState(() {
      _tab = i;
      _shrunk = false;
    });
  }

  void _onPlay(Track t, List<Track> queue) {
    if (audioHandler.current.value?.id == t.id) {
      _openPlayer();
      return;
    }
    final playable = queue.where((e) => e.kind == ItemKind.track).toList();
    final list = playable.isEmpty ? [t] : playable;
    final idx = list.indexWhere((e) => e.id == t.id);
    audioHandler.setQueue(list, idx < 0 ? 0 : idx).catchError((Object e) {
      audioHandler.errorMessage.value = 'Gagal memutar lagu';
    });
  }

  void _openPlayer() {
    if (audioHandler.current.value == null) return;
    final dur = Perf.instance.lite.value ? 220 : 380;
    Navigator.of(context).push(PageRouteBuilder<void>(
      pageBuilder: (_, __, ___) => const PlayerScreen(),
      transitionDuration: Duration(milliseconds: dur),
      reverseTransitionDuration: Duration(milliseconds: dur - 40),
      transitionsBuilder: (_, anim, __, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic)),
        child: child,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).padding.bottom;
    return PopScope(
      canPop: _tab == 0,
      onPopInvoked: (didPop) {
        if (!didPop) setState(() => _tab = 0); // back dari tab lain -> ke Beranda
      },
      child: Scaffold(
        extendBody: true,
        resizeToAvoidBottomInset: false,
        backgroundColor: C.bg,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [C.bg2, C.bg]),
          ),
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: Stack(
              children: [
                Positioned.fill(child: IndexedStack(index: _tab, children: _pages)),
                // Mini player + navigasi. Disembunyikan saat keyboard terbuka.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Builder(builder: (ctx) {
                    if (MediaQuery.of(ctx).viewInsets.bottom > 0) return const SizedBox.shrink();
                    return Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, inset + 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ValueListenableBuilder<Track?>(
                            valueListenable: audioHandler.current,
                            builder: (_, t, __) => AnimatedSwitcher(
                              duration: const Duration(milliseconds: 260),
                              transitionBuilder: (child, anim) => FadeTransition(
                                opacity: anim,
                                child: SlideTransition(
                                  position: Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(anim),
                                  child: child,
                                ),
                              ),
                              child: t == null
                                  ? const SizedBox.shrink(key: ValueKey('no_mini'))
                                  : Padding(
                                      key: const ValueKey('mini'),
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: MiniPlayer(track: t, onTap: _openPlayer),
                                    ),
                            ),
                          ),
                          LiquidNav(
                            index: _tab,
                            shrunk: _shrunk,
                            onChanged: _select,
                            onExpand: () => _setShrunk(false),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
