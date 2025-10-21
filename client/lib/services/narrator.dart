// Deterministic pseudo-random text generator for offline narration.
import 'dart:math';

class _XorShift32 {
  int _x;
  _XorShift32(int seed) : _x = seed == 0 ? 2463534242 : seed;
  int next() {
    int x = _x;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= (x >> 17);
    x ^= (x << 5) & 0xFFFFFFFF;
    _x = x & 0xFFFFFFFF;
    return _x;
  }
  double nextDouble() => (next() & 0xFFFFFF) / 0x1000000;
}

String generateNarration({required String prompt, required int seed, int sentences = 4}) {
  final base = prompt.trim().isEmpty ? 'You stand at the edge of a quiet world.' : prompt.trim();
  // Combine prompt hash with seed to stabilize output per prompt.
  final pHash = base.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0x7fffffff);
  final rng = _XorShift32((seed ^ pHash) & 0x7fffffff);

  const subjects = [
    'The wind', 'A distant bell', 'Footsteps', 'A whisper', 'Shadows',
    'Starlight', 'An old map', 'Faint music', 'A lantern', 'A doorway'
  ];
  const verbs = ['echo', 'guide', 'flicker', 'unfold', 'reveal', 'question', 'gather', 'scatter', 'breathe', 'fall'];
  const places = ['the valley', 'a forgotten street', 'the shoreline', 'an open gate', 'the old library', 'a crossroads'];
  const tones = ['calm', 'uncertain', 'hopeful', 'solemn', 'curious', 'restless'];

  String pick(List<String> list) => list[(rng.next() % list.length).abs()];

  final out = StringBuffer()
    ..writeln(base.endsWith('.') ? base : '$base.');
  for (var i = 0; i < sentences; i++) {
    final s = '${pick(subjects)} ${pick(verbs)} through ${pick(places)}, in a ${pick(tones)} hush.';
    out.writeln(s[0].toUpperCase() + s.substring(1));
  }
  return out.toString().trim();
}