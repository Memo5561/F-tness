import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'mannequin/exercise_animation.dart';
import 'mannequin/mannequin_view.dart';

/// Demo: pick an exercise, drag to rotate, toggle dark/light and playback.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MannequinShader.load(); // warm up: compile the shader before first use
  runApp(const DemoApp());
}

class DemoApp extends StatefulWidget {
  const DemoApp({super.key});
  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  bool dark = true;
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.light, scaffoldBackgroundColor: const Color(0xFFF5F5F5)),
      darkTheme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: const Color(0xFF121212)),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: DemoPage(onToggleTheme: () => setState(() => dark = !dark)),
    );
  }
}

class DemoPage extends StatefulWidget {
  final VoidCallback onToggleTheme;
  const DemoPage({super.key, required this.onToggleTheme});
  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  Map<String, ExerciseAnimation>? _anims;
  String _id = 'cal_front_lever';
  bool _playing = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final raw = jsonDecode(await rootBundle.loadString('assets/exercises.json')) as Map<String, dynamic>;
    final m = <String, ExerciseAnimation>{};
    raw.forEach((k, v) => m[k] = ExerciseAnimation.fromJson((v as Map).cast<String, dynamic>()));
    // allow ?ex=<id> in the web build URL
    final q = Uri.base.queryParameters['ex'];
    setState(() {
      _anims = m;
      if (q != null && m.containsKey(q)) _id = q;
    });
  }

  @override
  Widget build(BuildContext context) {
    final anims = _anims;
    return Scaffold(
      appBar: AppBar(
        title: const Text('3D Gliederpuppe'),
        actions: [
          IconButton(
            key: const Key('play'),
            icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
            onPressed: () => setState(() => _playing = !_playing),
          ),
          IconButton(key: const Key('theme'), icon: const Icon(Icons.brightness_6), onPressed: widget.onToggleTheme),
        ],
      ),
      body: anims == null
          ? const SizedBox.shrink()
          : Column(
              children: [
                Expanded(
                  child: Mannequin3DView(
                    key: ValueKey(_id),
                    animation: anims[_id]!,
                    playing: _playing,
                    usePreferredYaw: true,
                  ),
                ),
                SizedBox(
                  height: 56,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    children: [
                      for (final id in anims.keys)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(id.replaceFirst('cal_', '')),
                            selected: id == _id,
                            onSelected: (_) => setState(() => _id = id),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
