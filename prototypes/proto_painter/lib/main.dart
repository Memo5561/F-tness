import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'mannequin/exercise_animation.dart';
import 'mannequin/mannequin_view.dart';

void main() => runApp(const ProtoApp());

class ProtoApp extends StatefulWidget {
  const ProtoApp({super.key});

  @override
  State<ProtoApp> createState() => _ProtoAppState();
}

class _ProtoAppState extends State<ProtoApp> {
  bool _dark = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gliederpuppe',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: _dark ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: _dark ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
        colorSchemeSeed: Colors.teal,
      ),
      home: DemoPage(dark: _dark, onToggle: () => setState(() => _dark = !_dark)),
    );
  }
}

class DemoPage extends StatefulWidget {
  final bool dark;
  final VoidCallback onToggle;
  const DemoPage({super.key, required this.dark, required this.onToggle});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  List<(String, String, ExerciseAnimation)> _items = const [];
  int _index = 0;
  bool _playing = true;

  @override
  void initState() {
    super.initState();
    rootBundle.loadString('assets/exercises.json').then((s) {
      final list = jsonDecode(s) as List;
      setState(() {
        _items = [
          for (final e in list)
            ((e as Map)['id'] as String, e['n'] as String,
                ExerciseAnimation.fromJson(e.cast<String, dynamic>()))
        ];
        final fl = _items.indexWhere((e) => e.$1 == 'cal_front_lever');
        _index = fl < 0 ? 0 : fl;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.dark ? const Color(0xFF121212) : const Color(0xFFF5F5F5);
    if (_items.isEmpty) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final item = _items[_index];
    return Scaffold(
      appBar: AppBar(
        title: Text(item.$2, overflow: TextOverflow.ellipsis),
        backgroundColor: bg,
        actions: [
          IconButton(
            icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
            onPressed: () => setState(() => _playing = !_playing),
          ),
          IconButton(icon: const Icon(Icons.contrast), onPressed: widget.onToggle),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: Mannequin3DView(
            key: ValueKey(item.$1),
            animation: item.$3,
            initialYaw: item.$3.initialYaw,
            background: bg,
            playing: _playing,
          ),
        ),
        SizedBox(
          height: 56,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _items.length,
            itemBuilder: (c, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: ChoiceChip(
                label: Text(_items[i].$2),
                selected: i == _index,
                onSelected: (_) => setState(() => _index = i),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
