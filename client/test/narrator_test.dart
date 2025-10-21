import 'package:flutter_test/flutter_test.dart';
import 'package:uc4erpg_client/services/narrator.dart' as narrator;

void main() {
  test('deterministic output for fixed seed', () {
    final a = narrator.generateNarration(prompt: 'the gate', seed: 123);
    final b = narrator.generateNarration(prompt: 'the gate', seed: 123);
    expect(a, b);
  });

  test('different seeds produce different output', () {
    final a = narrator.generateNarration(prompt: 'the gate', seed: 1);
    final b = narrator.generateNarration(prompt: 'the gate', seed: 2);
    expect(a == b, isFalse);
  });
}