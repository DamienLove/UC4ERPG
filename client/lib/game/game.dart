import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flame/collisions.dart';
import 'package:flame/sprite.dart';
import 'package:flame_tiled/flame_tiled.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/material.dart' as m;
import 'package:flutter/foundation.dart' as f show ValueNotifier;
import 'package:flutter/services.dart' show LogicalKeyboardKey, RawKeyboard;
import 'dart:math' as math;
import 'state.dart';
import 'persist.dart';

class UC4EGame extends FlameGame with HasCollisionDetection {
  late final JoystickComponent _joystick;
  late final Player _player;
  late final SpriteSheet _labTiles;
  TiledComponent? _tiled;

  // Simple dialog state
  bool _inDialog = false;
  final List<_DialogLine> _dialogQueue = [];
  final f.ValueNotifier<_DialogLine?> activeLine = f.ValueNotifier<_DialogLine?>(null);
  final f.ValueNotifier<String?> interactHint = f.ValueNotifier<String?>(null);
  final GameState gs = GameState.instance;
  final Set<String> _spokenTo = {};
  final f.ValueNotifier<bool> _showConsent = f.ValueNotifier<bool>(false);
  final f.ValueNotifier<String> objective = f.ValueNotifier<String>('Objective: Speak with the doctors.');
  final f.ValueNotifier<bool> _showPause = f.ValueNotifier<bool>(false);
  final f.ValueNotifier<_Choice?> _choice = f.ValueNotifier<_Choice?>(null);
  bool _audioMuted = false;
  bool _actionDownPrev = false;
  bool _pauseDownPrev = false;
  bool _attackDownPrev = false;
  // Simple health + attack state
  final f.ValueNotifier<int> _hp = f.ValueNotifier<int>(5);
  int _maxHp = 5;
  double _attackCooldown = 0.0;
  double _invuln = 0.0;

  @override
  Future<void> onLoad() async {
    // Set a fixed camera zoom
    camera.viewfinder.zoom = 1.0;

    // Load tileset and TMX file
    images.prefix = 'assets/tilesets/';
    final labTilesImage = await images.load('lab_tiles.png');
    _labTiles = SpriteSheet(image: labTilesImage, srcSize: Vector2.all(32));

    images.prefix = 'assets/maps/';
    _tiled = await TiledComponent.load('lab.tmx', Vector2.all(32));
    add(_tiled!);

    // Reset prefix
    images.prefix = 'assets/';

    // Play ambient audio
    try {
      FlameAudio.bgm.initialize();
      FlameAudio.bgm.play('ambient_lab.wav', volume: 0.15);
    } catch (_) {}

    // Extract collision boundaries from the TMX file
    final collisions = _tiled!.tileMap.getLayer<ObjectGroup>('collisions');
    if (collisions != null) {
      for (final obj in collisions.objects) {
        add(Wall(rect: Rect.fromLTWH(obj.x, obj.y, obj.width, obj.height)));
      }
    }

    // Extract spawn points from the TMX file
    Vector2 playerPos = Vector2.zero();
    Vector2 elenaPos = Vector2(520, 340);
    Vector2 arunPos = Vector2(440, 300);
    Vector2 consentPos = Vector2(260, 480);
    final spawns = _tiled!.tileMap.getLayer<ObjectGroup>('spawns');
    if (spawns != null) {
      for (final o in spawns.objects) {
        final v = Vector2(o.x + (o.width / 2), o.y + (o.height / 2));
        switch (o.name) {
          case 'player':
            playerPos = v;
            break;
          case 'doc_elena':
            elenaPos = v;
            break;
          case 'doc_arun':
            arunPos = v;
            break;
          case 'consent_console':
            consentPos = v;
            break;
          case 'door_to_corridor':
            add(Door(position: v, label: 'To Corridor', targetScene: 'corridor', lockedUntilConsent: true));
            break;
          case 'enemy_drone':
            add(Drone(position: v));
            break;
        }
      }
    }
    // If no enemies placed in TMX, add a default one
    if (!children.any((c) => c is Drone)) {
      add(Drone(position: Vector2(playerPos.x + 120, playerPos.y + 40)));
    }

    // Initialize player and camera
    _player = Player(position: playerPos);
    add(_player);
    camera.follow(_player);

    // Add NPCs and interactive objects
    addAll([
      DoctorNPC(
          name: 'Dr. Elena Vega',
          position: elenaPos,
          lines: const [
            'Vitals are steady. The fungal lattice is responsive.',
            'When you are ready, we will proceed - your consent matters.',
          ],
          sprite: _labTiles.getSprite(0, 2)),
      DoctorNPC(
          name: 'Dr. Arun Patel',
          position: arunPos,
          lines: const [
            'Welcome. You are safe - take a slow breath.',
            'We are stabilizing the interface to the bio-compute mesh.',
          ],
          sprite: _labTiles.getSprite(0, 3)),
      ConsentConsole(position: consentPos),
    ]);
    // Add decorative props
    addAll([
      HologramPanel(position: elenaPos + Vector2(120, -120), size: Vector2(180, 100)),
      FungusVat(position: arunPos + Vector2(-160, 60)),
      BioRack(position: consentPos + Vector2(160, -60)),
    ]);

    // Add the joystick for player movement
    _joystick = JoystickComponent(
      knob: CircleComponent(radius: 22, paint: Paint()..color = m.Colors.indigo),
      background: CircleComponent(radius: 44, paint: Paint()..color = m.Colors.indigo.withOpacity(0.2)),
      margin: const m.EdgeInsets.only(left: 24, bottom: 24),
    );
    add(_joystick);

    // Show the HUD
    overlays.add('HUD');

    // Load any saved game state
    await Persist.loadInto(gs);
  }

  @override
  void update(double dt) {
    super.update(dt);
    // Move the player based on joystick and keyboard input
    if (!_inDialog) {
      final delta = _computeInput();
      _player.moveWithCollision(delta, dt, children.whereType<Wall>());
    }

    // Show or hide the interaction hint
    if (!_inDialog) {
      final target = _nearestInteractable();
      interactHint.value = target?.$2; // label
    } else {
      interactHint.value = null;
    }

    // Keep the joystick anchored to the screen
    final halfW = size.x / 2;
    final halfH = size.y / 2;
    final joyOffset = Vector2(24 + 44, 24 + 44); // margin + radius
    _joystick.position = Vector2(
      camera.viewfinder.position.x - halfW + joyOffset.x,
      camera.viewfinder.position.y + halfH - joyOffset.y,
    );
    // Update cooldown timers
    if (_attackCooldown > 0) {
      _attackCooldown = math.max(0, _attackCooldown - dt);
    }
    if (_invuln > 0) _invuln = math.max(0, _invuln - dt);

    // Handle enemy contact damage
    for (final d in children.whereType<Drone>()) {
      final dist = d.position.distanceTo(_player.position);
      if (dist < 20 && _invuln <= 0) {
        _applyDamage(1, (_player.position - d.position).normalized() * 40);
        break;
      }
    }
  }

  Vector2 _computeInput() {
    final d = _joystick.delta.clone();
    // Keyboard input
    final pressed = RawKeyboard.instance.keysPressed;
    double x = 0, y = 0;
    if (pressed.contains(LogicalKeyboardKey.keyA) || pressed.contains(LogicalKeyboardKey.arrowLeft)) x -= 1;
    if (pressed.contains(LogicalKeyboardKey.keyD) || pressed.contains(LogicalKeyboardKey.arrowRight)) x += 1;
    if (pressed.contains(LogicalKeyboardKey.keyW) || pressed.contains(LogicalKeyboardKey.arrowUp)) y -= 1;
    if (pressed.contains(LogicalKeyboardKey.keyS) || pressed.contains(LogicalKeyboardKey.arrowDown)) y += 1;
    if (x != 0 || y != 0) {
      final k = Vector2(x, y).normalized();
      d.add(k);
    }
    // Action button
    final actionDown = pressed.contains(LogicalKeyboardKey.space) ||
        pressed.contains(LogicalKeyboardKey.enter) ||
        pressed.contains(LogicalKeyboardKey.keyE);
    if (actionDown && !_actionDownPrev) {
      onActionPressed();
    }
    _actionDownPrev = actionDown;
    // Pause button
    final pauseDown = pressed.contains(LogicalKeyboardKey.escape);
    if (pauseDown && !_pauseDownPrev) {
      _showPause.value = !_showPause.value;
    }
    _pauseDownPrev = pauseDown;
    // Attack button
    final attackDown = pressed.contains(LogicalKeyboardKey.keyB);
    if (attackDown && !_attackDownPrev) {
      onAttackPressed();
    }
    _attackDownPrev = attackDown;
    return d;
  }

  // Handle the action button press
  void onActionPressed() {
    if (_inDialog) {
      _advanceDialog();
      return;
    }
    // Find the closest interactable object
    final nearest = _nearestInteractable();
    if (nearest != null) {
      final kind = nearest.$1;
      if (kind is DoctorNPC) {
        _markSpoken(kind.name);
        _presentDoctorChoice(kind.name);
      } else if (kind is Inspectable) {
        if (kind is ConsentConsole) {
          if (_spokenTo.contains('Dr. Elena Vega') && _spokenTo.contains('Dr. Arun Patel')) {
            _presentConsent();
          } else {
            _startDialog(kind.label, const [
              'Please consult with both doctors before proceeding.',
            ]);
            objective.value = 'Speak with both doctors before consenting.';
          }
        } else if (kind is Door) {
          _tryTransition(kind);
        } else {
          _startDialog(kind.label, kind.lines);
        }
      }
    }
  }

  // Handle the attack button press
  void onAttackPressed() {
    if (_inDialog) return;
    if (_attackCooldown > 0) return;
    _attackCooldown = 0.6; // seconds
    add(Pulse(origin: _player.position.clone(), maxRadius: 96, duration: 0.25));
  }

  // Find the closest interactable object
  (Object, String)? _nearestInteractable() {
    Object? nearest;
    String? label;
    double best = 84; // px
    for (final c in children) {
      if (c is DoctorNPC) {
        final d = _player.position.distanceTo(c.position);
        if (d < best) {
          best = d;
          nearest = c;
          label = c.name;
        }
      } else if (c is Inspectable) {
        final d = _player.position.distanceTo(c.position);
        if (d < best) {
          best = d;
          nearest = c;
          label = c.label;
        }
      }
    }
    if (nearest == null || label == null) return null;
    return (nearest, label);
  }

  // Start a dialog
  void _startDialog(String speaker, List<String> lines) {
    _dialogQueue
      ..clear()
      ..addAll(lines.map((t) => _DialogLine(speaker: speaker, text: t)));
    _inDialog = true;
    _advanceDialog();
  }

  // Advance to the next line of dialog
  void _advanceDialog() {
    if (_dialogQueue.isEmpty) {
      _inDialog = false;
      activeLine.value = null;
      return;
    }
    activeLine.value = _dialogQueue.removeAt(0);
  }

  // Mark an NPC as spoken to
  void _markSpoken(String name) {
    _spokenTo.add(name);
    gs.markSpoken(name);
    if (_spokenTo.contains('Dr. Elena Vega') && _spokenTo.contains('Dr. Arun Patel')) {
      objective.value = 'Objective: Approach the Consent Console (A to consent)';
    }
  }

  // Show the consent dialog
  void _presentConsent() {
    _inDialog = false;
    activeLine.value = null;
    _showConsent.value = true;
  }

  // Handle the player's consent choice
  void onConsentChoice(bool consented) {
    _showConsent.value = false;
    if (consented) {
      objective.value = 'Consent recorded. Calibration starting…';
      gs.setConsent(true);
      _startDialog('System', const [
        'Consent acknowledged. Initializing calibration sequence.',
        'Hold steady — establishing cognitive link to bio-compute lattice.',
      ]);
    } else {
      _startDialog('System', const [
        'Consent deferred. You may speak to the doctors again or proceed later.',
      ]);
      objective.value = 'Objective: Speak with Dr. Vega/Dr. Patel or consent when ready.';
    }
  }

  // Apply damage to the player
  void _applyDamage(int dmg, Vector2 knockback) {
    if (_hp.value <= 0) return;
    _hp.value = math.max(0, _hp.value - dmg);
    _player.position += knockback;
    _invuln = 1.2;
    // TODO: show flash or dialog when hp hits 0
  }

  // Try to transition to a new scene
  void _tryTransition(Door door) {
    if (door.lockedUntilConsent && !gs.consentGiven.value) {
      _startDialog('Door', const ['Locked. Consent required to proceed.']);
      return;
    }
    _loadScene(door.targetScene);
  }

  // Show the doctor choice dialog
  void _presentDoctorChoice(String name) {
    if (name.contains('Elena')) {
      _choice.value = _Choice(
        title: 'Dr. Elena Vega',
        options: [
          _ChoiceOpt(id: 'elena_lattice', label: 'What is the lattice?'),
          _ChoiceOpt(id: 'elena_ready', label: 'Am I ready to proceed?'),
          _ChoiceOpt(id: 'elena_calibration', label: 'What is calibration?'),
          _ChoiceOpt(id: 'elena_consent', label: 'What does consent cover?'),
        ],
      );
    } else if (name.contains('Arun')) {
      _choice.value = _Choice(
        title: 'Dr. Arun Patel',
        options: [
          _ChoiceOpt(id: 'arun_feel', label: 'How will it feel?'),
          _ChoiceOpt(id: 'arun_wait', label: 'I need a moment.'),
          _ChoiceOpt(id: 'arun_monitor', label: 'What will you monitor?'),
          _ChoiceOpt(id: 'arun_controls', label: 'Can I stop at any time?'),
        ],
      );
    } else {
      _startDialog(name, const ['Hello.']);
    }
  }

  // Handle the player's choice in a dialog
  void _onChoice(String id) {
    _choice.value = null;
    switch (id) {
      case 'elena_lattice':
        gs.learn('elena_lattice');
        _startDialog('Dr. Elena Vega', const [
          'A living network of fungal mycelia acting as a bio-compute mesh.',
          'It adapts to you as much as you adapt to it.',
        ]);
        break;
      case 'elena_ready':
        gs.learn('elena_ready');
        _startDialog('Dr. Elena Vega', const [
          'Your vitals are stable and responses within safe thresholds.',
          'When you are ready, confirm consent at the console.',
        ]);
        break;
      case 'elena_calibration':
        gs.learn('elena_calibration');
        _startDialog('Dr. Elena Vega', const [
          'Calibration aligns your neural patterns with the lattice feedback.',
          'It improves clarity and reduces cognitive load during sessions.',
        ]);
        break;
      case 'elena_consent':
        gs.learn('elena_consent');
        _startDialog('Dr. Elena Vega', const [
          'Scope: data collection, monitoring, and guided interaction with the lattice.',
          'You can revoke consent at any time; we will disengage safely.',
        ]);
        break;
      case 'arun_feel':
        gs.learn('arun_feel');
        _startDialog('Dr. Arun Patel', const [
          'A slight pressure behind the eyes, followed by clarity.',
          'Focus on your breath. We will monitor continuously.',
        ]);
        break;
      case 'arun_wait':
        gs.learn('arun_wait');
        _startDialog('Dr. Arun Patel', const [
          'Take the time you need. Speak to us if anything feels off.',
        ]);
        break;
      case 'arun_monitor':
        gs.learn('arun_monitor');
        _startDialog('Dr. Arun Patel', const [
          'EEG, heart rate variability, and ocular micro-saccades.',
          'We also track subjective comfort; your feedback matters.',
        ]);
        break;
      case 'arun_controls':
        gs.learn('arun_controls');
        _startDialog('Dr. Arun Patel', const [
          'Yes. Say "Stop" or open the pause menu and select Reset.',
          'We will immediately disengage and stabilize the interface.',
        ]);
        break;
    }
  }

  // Load a new scene
  Future<void> _loadScene(String scene) async {
    // Remove all the components from the previous scene
    final toRemove = children
        .where((c) =>
            c is TiledComponent ||
            c is Wall ||
            c is DoctorNPC ||
            c is HologramPanel ||
            c is ConsoleStation ||
            c is FungusVat ||
            c is BioRack ||
            c is ConsentConsole ||
            c is Door)
        .toList();
    for (final c in toRemove) {
      c.removeFromParent();
    }

    // Load the new TMX file
    String mapPath;
    switch (scene) {
      case 'lab':
        mapPath = 'maps/lab.tmx';
        break;
      case 'corridor':
        mapPath = 'maps/corridor.tmx';
        break;
      case 'observation':
        mapPath = 'maps/observation.tmx';
        break;
      default:
        mapPath = 'maps/lab.tmx';
    }
    _tiled = await TiledComponent.load(mapPath, Vector2.all(32));
    add(_tiled!);
    // Play the correct ambient audio
    if (scene == 'lab' || scene == 'observation' || scene == 'corridor') {
      if (!FlameAudio.bgm.isPlaying) {
        FlameAudio.bgm.play('ambient_lab.wav', volume: 0.15);
      }
    } else {
      FlameAudio.bgm.stop();
    }

    // Add collisions
    final collisions = _tiled!.tileMap.getLayer<ObjectGroup>('collisions');
    if (collisions != null) {
      for (final obj in collisions.objects) {
        add(Wall(rect: Rect.fromLTWH(obj.x, obj.y, obj.width, obj.height)));
      }
    }

    // Add spawns and objects
    Vector2 playerPos = _player.position.clone();
    final spawns = _tiled!.tileMap.getLayer<ObjectGroup>('spawns');
    if (spawns != null) {
      for (final o in spawns.objects) {
        final v = Vector2(o.x + (o.width / 2), o.y + (o.height / 2));
        switch (o.name) {
          case 'player':
            playerPos = v;
            break;
          case 'doc_elena':
            add(DoctorNPC(
                name: 'Dr. Elena Vega',
                position: v,
                lines: const [
                  'Vitals are steady. The fungal lattice is responsive.',
                  'When you are ready, we will proceed — your consent matters.',
                ],
                sprite: _labTiles.getSprite(0, 2)));
            break;
          case 'doc_arun':
            add(DoctorNPC(
                name: 'Dr. Arun Patel',
                position: v,
                lines: const [
                  'Welcome. You are safe — take a slow breath.',
                  'We are stabilizing the interface to the bio-compute mesh.',
                ],
                sprite: _labTiles.getSprite(0, 3)));
            break;
          case 'consent_console':
            add(ConsentConsole(position: v));
            break;
          case 'door_to_corridor':
            add(Door(position: v, label: 'To Corridor', targetScene: 'corridor', lockedUntilConsent: true));
            break;
          case 'door_to_lab':
            add(Door(position: v, label: "To Doctors' Lab", targetScene: 'lab', lockedUntilConsent: false));
            break;
          case 'door_to_observation':
            add(Door(position: v, label: 'To Observation', targetScene: 'observation', lockedUntilConsent: true));
            break;
          case 'enemy_drone':
            add(Drone(position: v));
            break;
        }
      }
    }
    // Add a fallback enemy
    if (!children.any((c) => c is Drone)) {
      add(Drone(position: playerPos + Vector2(140, -20)));
    }

    // Update the player's position and the camera
    _player.position = playerPos;
    camera.follow(_player);
    // Update the section name
    switch (scene) {
      case 'lab':
        gs.section.value = "Doctors' Lab";
        break;
      case 'corridor':
        gs.section.value = 'Corridor';
        break;
      case 'observation':
        gs.section.value = 'Observation Room';
        break;
    }
  }
}

class Wall extends PositionComponent with CollisionCallbacks {
  final Rect rect;
  Wall({required this.rect});
  @override
  Future<void> onLoad() async {
    position = Vector2(rect.left, rect.top);
    size = Vector2(rect.width, rect.height);
    add(RectangleHitbox());
  }
  @override
  void render(Canvas canvas) {
    final paint = Paint()..color = m.Colors.indigo.withOpacity(0.15);
    canvas.drawRect(size.toRect(), paint);
  }
}

class Player extends PositionComponent with CollisionCallbacks {
  final double speed = 220; // units per second

  Player({required Vector2 position}) {
    this.position = position;
    size = Vector2.all(40);
    anchor = Anchor.center;
  }

  @override
  Future<void> onLoad() async {
    add(RectangleHitbox());
  }

  void moveWithCollision(Vector2 input, double dt, Iterable<Wall> walls) {
    if (input.length2 == 0) return;
    final dir = input.normalized();
    var next = position + dir * speed * dt;
    // simple AABB against walls; move X then Y
    final half = size / 2;
    // X
    var cand = Vector2(next.x, position.y);
    if (_collides(cand, half, walls)) {
      cand.x = position.x; // cancel X
    }
    // Y
    next = Vector2(cand.x, next.y);
    if (_collides(next, half, walls)) {
      next.y = position.y; // cancel Y
    }
    position = next;
  }

  bool _collides(Vector2 center, Vector2 half, Iterable<Wall> walls) {
    final r = Rect.fromLTWH(center.x - half.x, center.y - half.y, size.x, size.y);
    for (final w in walls) {
      final wr = Rect.fromLTWH(w.position.x, w.position.y, w.size.x, w.size.y);
      if (r.overlaps(wr)) return true;
    }
    return false;
  }

  @override
  void render(Canvas canvas) {
    final body = Paint()..color = m.Colors.cyanAccent;
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = m.Colors.blueGrey.shade900;
    canvas.drawCircle(Offset.zero, size.x * 0.42, body);
    canvas.drawCircle(Offset.zero, size.x * 0.42, border);
  }
}

// Simple interactable objects for the lab
abstract class Inspectable extends PositionComponent {
  String get label;
  List<String> get lines;
}

class HologramPanel extends PositionComponent implements Inspectable {
  @override
  final String label = 'Holographic Interface';
  @override
  final List<String> lines = const [
    'Projected UI active. Bio-compute mesh online.',
    'Touchless input detected. Displaying neural telemetry.'
  ];
  double _t = 0;
  HologramPanel({required super.position, required super.size}) {
    anchor = Anchor.topLeft;
  }
  @override
  void update(double dt) {
    _t += dt;
  }

  @override
  void render(Canvas canvas) {
    final base = Paint()..color = m.Colors.cyanAccent.withOpacity(0.18 + 0.12 * (0.5 + 0.5 * math.sin(_t * 2)));
    final glow = Paint()
      ..color = m.Colors.cyanAccent.withOpacity(0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 6);
    canvas.drawRRect(RRect.fromRectAndRadius(size.toRect(), const Radius.circular(10)), base);
    canvas.drawRRect(RRect.fromRectAndRadius(size.toRect(), const Radius.circular(10)), glow);
    // grid lines
    final grid = Paint()..color = m.Colors.white10;
    for (double x = 10; x < size.x; x += 20) {
      canvas.drawLine(Offset(x, 6), Offset(x, size.y - 6), grid);
    }
    for (double y = 6; y < size.y; y += 18) {
      canvas.drawLine(Offset(10, y), Offset(size.x - 10, y), grid);
    }
  }
}

class ConsoleStation extends PositionComponent implements Inspectable {
  @override
  final String label = 'Console Station';
  @override
  final List<String> lines = const [
    'Authentication accepted. Research log loaded.',
    'Fungal lattice pathways recalibrated for bio-computation.'
  ];
  ConsoleStation({required super.position}) {
    size = Vector2(48, 36);
    anchor = Anchor.center;
  }
  @override
  void render(Canvas canvas) {
    final base = Paint()..color = m.Colors.blueGrey.shade800;
    canvas.drawRRect(RRect.fromRectAndRadius(size.toRect(), const Radius.circular(6)), base);
    final screen = Paint()..color = m.Colors.lightBlueAccent.withOpacity(0.8);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(6, 6, size.x - 12, size.y - 16), const Radius.circular(4)), screen);
    final stand = Paint()..color = m.Colors.blueGrey.shade700;
    canvas.drawRect(Rect.fromLTWH(size.x / 2 - 6, size.y - 16, 12, 16), stand);
  }
}

class FungusVat extends PositionComponent implements Inspectable {
  @override
  final String label = 'Fungal Bio-Vat';
  @override
  final List<String> lines = const [
    'Suspended mycelial network in nutrient gel.',
    'Cognitive throughput nominal; preparing query channel.'
  ];
  FungusVat({required super.position}) {
    size = Vector2(64, 96);
    anchor = Anchor.center;
  }
  @override
  void render(Canvas canvas) {
    final glass = Paint()..color = m.Colors.greenAccent.withOpacity(0.28);
    canvas.drawRRect(RRect.fromRectAndRadius(size.toRect(), const Radius.circular(12)), glass);
    final liquid = Paint()..color = m.Colors.greenAccent.withOpacity(0.45);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(6, 10, size.x - 12, size.y - 20), const Radius.circular(8)), liquid);
    final frame = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = m.Colors.greenAccent;
    canvas.drawRRect(RRect.fromRectAndRadius(size.toRect(), const Radius.circular(12)), frame);
  }
}

class BioRack extends PositionComponent implements Inspectable {
  @override
  final String label = 'Specimen Rack';
  @override
  final List<String> lines = const [
    'Cultures indexed. Access constrained to principal investigators.',
  ];
  BioRack({required super.position}) {
    size = Vector2(120, 32);
    anchor = Anchor.center;
  }
  @override
  void render(Canvas canvas) {
    final shelf = Paint()..color = m.Colors.blueGrey.shade700;
    canvas.drawRRect(RRect.fromRectAndRadius(size.toRect(), const Radius.circular(4)), shelf);
    final vial = Paint()..color = m.Colors.purpleAccent.withOpacity(0.8);
    for (double x = 10; x < size.x - 8; x += 18) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, 8, 10, 16), const Radius.circular(3)), vial);
    }
  }
}

class ConsentConsole extends PositionComponent implements Inspectable {
  @override
  final String label = 'Consent Console';
  @override
  final List<String> lines = const [
    'Touch to confirm informed consent.',
    'Logging consent… secure channel engaged.'
  ];
  ConsentConsole({required super.position}) {
    size = Vector2(60, 44);
    anchor = Anchor.center;
  }
  @override
  void render(Canvas canvas) {
    final base = Paint()..color = m.Colors.blueGrey.shade800;
    canvas.drawRRect(RRect.fromRectAndRadius(size.toRect(), const Radius.circular(8)), base);
    final screen = Paint()..color = m.Colors.tealAccent.withOpacity(0.85);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(6, 6, size.x - 12, size.y - 16), const Radius.circular(6)), screen);
    final btn = Paint()..color = m.Colors.greenAccent;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.x / 2 - 10, size.y - 14, 20, 8), const Radius.circular(3)), btn);
  }
}

class Door extends PositionComponent implements Inspectable {
  @override
  final String label;
  final String targetScene;
  final bool lockedUntilConsent;
  @override
  List<String> get lines => const [
        'A sealed bulkhead door with biometric controls.',
      ];
  Door({required Vector2 position, required String label, required this.targetScene, this.lockedUntilConsent = false})
      : label = 'Door: ' + label {
    this.position = position;
    size = Vector2(48, 12);
    anchor = Anchor.center;
  }
  @override
  void render(Canvas canvas) {
    final frame = Paint()..color = m.Colors.blueGrey.shade600;
    canvas.drawRRect(RRect.fromRectAndRadius(size.toRect(), const Radius.circular(4)), frame);
    final strip = Paint()..color = m.Colors.lightBlueAccent;
    canvas.drawRect(Rect.fromLTWH(4, size.y / 2 - 2, size.x - 8, 4), strip);
  }
}

class DoctorNPC extends SpriteComponent {
  final String name;
  final List<String> lines;
  DoctorNPC({required this.name, required Vector2 position, required this.lines, required Sprite sprite})
      : super(sprite: sprite, position: position) {
    size = Vector2(36, 36);
    anchor = Anchor.center;
  }
}

class Drone extends PositionComponent with CollisionCallbacks {
  int hp = 3;
  final double speed = 60;
  Vector2 _vel = Vector2.zero();
  double _t = 0;
  Drone({required Vector2 position}) {
    this.position = position;
    size = Vector2(28, 28);
    anchor = Anchor.center;
  }
  @override
  Future<void> onLoad() async {
    add(RectangleHitbox());
  }
  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    final game = findGame() as UC4EGame?;
    if (game != null) {
      final toPlayer = game._player.position - position;
      final dist = toPlayer.length;
      if (dist < 180) {
        _vel = toPlayer.normalized() * speed;
      } else {
        final ang = _t + (hashCode % 100) * 0.01;
        _vel = Vector2(math.cos(ang), math.sin(ang)) * (speed * 0.5);
      }
    }
    position += _vel * dt;
    if (hp <= 0) removeFromParent();
  }
  void applyDamage(int dmg, Vector2 knockback) {
    hp -= dmg;
    position += knockback;
  }
  @override
  void render(Canvas canvas) {
    final body = Paint()..color = m.Colors.deepPurpleAccent;
    canvas.drawRRect(RRect.fromRectAndRadius(size.toRect(), const Radius.circular(6)), body);
    final eye = Paint()..color = m.Colors.white;
    canvas.drawCircle(Offset(size.x / 2, size.y / 2), 3, eye);
  }
}

class Pulse extends PositionComponent {
  final Vector2 origin;
  final double maxRadius;
  final double duration;
  double _time = 0;
  final Set<Drone> _hit = <Drone>{};
  Pulse({required this.origin, required this.maxRadius, required this.duration}) {
    position = origin.clone();
    size = Vector2.zero();
    anchor = Anchor.center;
    priority = 50;
  }
  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    if (_time >= duration) {
      removeFromParent();
      return;
    }
    final r = (_time / duration) * maxRadius;
    size = Vector2.all(r * 2);
    final game = findGame() as UC4EGame?;
    if (game != null) {
      for (final c in game.children.whereType<Drone>()) {
        if (_hit.contains(c)) continue;
        final d = c.position.distanceTo(origin);
        if (d <= r) {
          final kb = (c.position - origin).normalized() * 24;
          c.applyDamage(1, kb);
          _hit.add(c);
        }
      }
    }
  }
  @override
  void render(Canvas canvas) {
    final r = size.x / 2;
    final glow = Paint()
      ..color = m.Colors.tealAccent.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 8);
    canvas.drawCircle(Offset.zero, r, glow);
    final ring = Paint()
      ..color = m.Colors.tealAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(Offset.zero, r, ring);
  }
}

class _DialogLine {
  final String speaker;
  final String text;
  _DialogLine({required this.speaker, required this.text});
}

class _ChoiceOpt {
  final String id;
  final String label;
  _ChoiceOpt({required this.id, required this.label});
}

class _Choice {
  final String title;
  final List<_ChoiceOpt> options;
  _Choice({required this.title, required this.options});
}

class GameScreen extends m.StatelessWidget {
  const GameScreen({super.key});
  @override
  m.Widget build(m.BuildContext context) {
    final game = UC4EGame();
    return m.Scaffold(
      appBar: m.AppBar(title: const m.Text('UC4ERPG – Play')),
      body: GameWidget(
        game: game,
        overlayBuilderMap: {
          'HUD': (ctx, g) => _HUD(game: game),
        },
      ),
    );
  }
}

class _HUD extends m.StatelessWidget {
  final UC4EGame game;
  const _HUD({required this.game});
  String? _portraitFor(String speaker) {
    if (speaker.contains('Elena')) return 'assets/portraits/dr_elena.png';
    if (speaker.contains('Arun')) return 'assets/portraits/dr_arun.png';
    return null;
  }

  @override
  m.Widget build(m.BuildContext context) {
    return m.Stack(children: [
      // Hearts (top-right)
      m.Positioned(
        right: 12,
        top: 10,
        child: m.ValueListenableBuilder<int>(
          valueListenable: game._hp,
          builder: (context, hp, _) {
            final hearts = <m.Widget>[];
            for (var i = 0; i < game._maxHp; i++) {
              final filled = i < hp;
              hearts.add(m.Icon(
                filled ? m.Icons.favorite : m.Icons.favorite_border,
                color: filled ? m.Colors.redAccent : m.Colors.white30,
                size: 18,
              ));
            }
            return m.Container(
              padding: const m.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: m.BoxDecoration(
                color: m.Colors.black.withOpacity(0.45),
                borderRadius: m.BorderRadius.circular(8),
              ),
              child: m.Row(mainAxisSize: m.MainAxisSize.min, children: hearts),
            );
          },
        ),
      ),
      // Consent choice overlay
      m.ValueListenableBuilder<bool>(
        valueListenable: game._showConsent,
        builder: (context, show, _) {
          if (!show) return const m.SizedBox.shrink();
          return m.Container(
            color: m.Colors.black.withOpacity(0.55),
            alignment: m.Alignment.center,
            child: m.Container(
              padding: const m.EdgeInsets.all(16),
              decoration: m.BoxDecoration(
                color: m.Colors.grey.shade900,
                borderRadius: m.BorderRadius.circular(12),
                border: m.Border.all(color: m.Colors.white24),
              ),
              width: 360,
              child: m.Column(
                mainAxisSize: m.MainAxisSize.min,
                crossAxisAlignment: m.CrossAxisAlignment.stretch,
                children: [
                  const m.Text('Confirm Informed Consent', style: m.TextStyle(fontSize: 18, fontWeight: m.FontWeight.bold)),
                  const m.SizedBox(height: 8),
                  const m.Text('Proceed with calibration and establish a cognitive link to the bio-compute lattice?'),
                  const m.SizedBox(height: 16),
                  m.Row(
                    mainAxisAlignment: m.MainAxisAlignment.spaceBetween,
                    children: [
                      m.OutlinedButton(onPressed: () => game.onConsentChoice(false), child: const m.Text('Not yet')),
                      m.ElevatedButton(onPressed: () => game.onConsentChoice(true), child: const m.Text('Consent')),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
      // Doctor choice overlay
      m.ValueListenableBuilder<_Choice?>(
        valueListenable: game._choice,
        builder: (context, choice, _) {
          if (choice == null) return const m.SizedBox.shrink();
          return m.Container(
            color: m.Colors.black.withOpacity(0.55),
            alignment: m.Alignment.center,
            child: m.Container(
              padding: const m.EdgeInsets.all(16),
              decoration: m.BoxDecoration(
                color: m.Colors.grey.shade900,
                borderRadius: m.BorderRadius.circular(12),
                border: m.Border.all(color: m.Colors.white24),
              ),
              width: 360,
              child: m.Column(
                mainAxisSize: m.MainAxisSize.min,
                crossAxisAlignment: m.CrossAxisAlignment.stretch,
                children: [
                  m.Text(choice.title, style: const m.TextStyle(fontSize: 18, fontWeight: m.FontWeight.bold)),
                  const m.SizedBox(height: 8),
                  for (final opt in choice.options)
                    m.Padding(
                      padding: const m.EdgeInsets.only(top: 8),
                      child: m.ElevatedButton(
                        onPressed: () => game._onChoice(opt.id),
                        child: m.Text(opt.label),
                      ),
                    ),
                  m.TextButton(onPressed: () => game._choice.value = null, child: const m.Text('Close')),
                ],
              ),
            ),
          );
        },
      ),
      // Chapter / Section / Objectives (top center)
      m.Positioned(
        top: 10,
        left: 12,
        right: 12,
        child: m.Center(
          child: m.Container(
            padding: const m.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: m.BoxDecoration(
              color: m.Colors.black.withOpacity(0.45),
              borderRadius: m.BorderRadius.circular(8),
            ),
            child: m.Column(
              mainAxisSize: m.MainAxisSize.min,
              children: [
                m.ValueListenableBuilder<String>(
                  valueListenable: game.gs.chapter,
                  builder: (context, ch, _) =>
                      m.Text(ch, style: const m.TextStyle(color: m.Colors.white, fontWeight: m.FontWeight.bold)),
                ),
                m.ValueListenableBuilder<String>(
                  valueListenable: game.gs.section,
                  builder: (context, sec, _) => m.Text(sec, style: const m.TextStyle(color: m.Colors.white70)),
                ),
                const m.SizedBox(height: 4),
                m.ValueListenableBuilder(
                  valueListenable: game.gs.quest,
                  builder: (context, q, _) {
                    return m.Column(
                      mainAxisSize: m.MainAxisSize.min,
                      children: [
                        for (final item in q.items)
                          m.Row(
                            mainAxisSize: m.MainAxisSize.min,
                            children: [
                              m.Icon(item.complete ? m.Icons.check_circle : m.Icons.radio_button_unchecked,
                                  size: 16, color: item.complete ? m.Colors.greenAccent : m.Colors.white38),
                              const m.SizedBox(width: 6),
                              m.Text(item.text, style: const m.TextStyle(color: m.Colors.white)),
                            ],
                          ),
                        const m.SizedBox(height: 6),
                        m.ValueListenableBuilder<Set<String>>(
                          valueListenable: game.gs.knowledge,
                          builder: (context, known, _) {
                            final topics = <Map<String, String>>[
                              {'id': 'elena_lattice', 'label': 'What is the lattice?'},
                              {'id': 'elena_ready', 'label': 'Am I ready to proceed?'},
                              {'id': 'elena_calibration', 'label': 'What is calibration?'},
                              {'id': 'elena_consent', 'label': 'What does consent cover?'},
                              {'id': 'arun_feel', 'label': 'How will it feel?'},
                              {'id': 'arun_wait', 'label': 'I need a moment.'},
                              {'id': 'arun_monitor', 'label': 'What will you monitor?'},
                              {'id': 'arun_controls', 'label': 'Can I stop at any time?'},
                            ];
                            return m.Column(
                              mainAxisSize: m.MainAxisSize.min,
                              crossAxisAlignment: m.CrossAxisAlignment.start,
                              children: [
                                m.Text('Learned', style: const m.TextStyle(color: m.Colors.white70, fontSize: 12)),
                                for (final t in topics)
                                  m.Row(
                                    mainAxisSize: m.MainAxisSize.min,
                                    children: [
                                      m.Icon(known.contains(t['id']) ? m.Icons.check : m.Icons.remove,
                                          size: 14, color: known.contains(t['id']) ? m.Colors.greenAccent : m.Colors.white24),
                                      const m.SizedBox(width: 4),
                                      m.Text(t['label']!, style: const m.TextStyle(color: m.Colors.white, fontSize: 12)),
                                    ],
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      // Top-right quick actions (Save / Reset)
      m.Positioned(
        right: 12,
        top: 12,
        child: m.Row(children: [
          m.IconButton(
            tooltip: 'Menu',
            onPressed: () => game._showPause.value = true,
            icon: const m.Icon(m.Icons.more_horiz, color: m.Colors.white),
          ),
          m.IconButton(
            tooltip: 'Save',
            onPressed: () async {
              await Persist.save(game.gs);
              // Feedback via dialog line without blocking gameplay
              game._startDialog('System', const ['Progress saved.']);
            },
            icon: const m.Icon(m.Icons.save, color: m.Colors.white),
          ),
          m.IconButton(
            tooltip: 'Reset Progress',
            onPressed: () async {
              await Persist.reset();
              game.gs.consentGiven.value = false;
              game.gs.startSection(
                chapterName: 'Chapter 1: Arrival',
                sectionName: "Doctors' Lab",
                newQuest: Quest(
                  id: 'arrival_lab_intro',
                  title: "Meet the Doctors & Consent",
                  items: [
                    ObjectiveItem(id: 'talk_elena', text: 'Talk to Dr. Elena Vega'),
                    ObjectiveItem(id: 'talk_arun', text: 'Talk to Dr. Arun Patel'),
                    ObjectiveItem(id: 'consent', text: 'Confirm informed consent'),
                  ],
                ),
              );
              game._startDialog('System', const ['Progress reset.']);
            },
            icon: const m.Icon(m.Icons.refresh, color: m.Colors.white),
          ),
        ]),
      ),
      // Pause menu overlay
      m.ValueListenableBuilder<bool>(
        valueListenable: game._showPause,
        builder: (context, show, _) {
          if (!show) return const m.SizedBox.shrink();
          return m.Container(
            color: m.Colors.black.withOpacity(0.55),
            alignment: m.Alignment.center,
            child: m.Container(
              padding: const m.EdgeInsets.all(16),
              decoration: m.BoxDecoration(
                color: m.Colors.grey.shade900,
                borderRadius: m.BorderRadius.circular(12),
                border: m.Border.all(color: m.Colors.white24),
              ),
              width: 320,
              child: m.Column(
                mainAxisSize: m.MainAxisSize.min,
                crossAxisAlignment: m.CrossAxisAlignment.stretch,
                children: [
                  const m.Text('Pause', style: m.TextStyle(fontSize: 18, fontWeight: m.FontWeight.bold)),
                  const m.SizedBox(height: 10),
                  m.ElevatedButton(onPressed: () => game._showPause.value = false, child: const m.Text('Resume')),
                  m.ElevatedButton(
                      onPressed: () async {
                        await Persist.save(game.gs);
                        game._startDialog('System', const ['Progress saved.']);
                        game._showPause.value = false;
                      },
                      child: const m.Text('Save')),
                  m.OutlinedButton(
                      onPressed: () async {
                        await Persist.reset();
                        game.gs.consentGiven.value = false;
                        game.gs.startSection(chapterName: 'Chapter 1: Arrival', sectionName: "Doctors' Lab");
                        game._startDialog('System', const ['Progress reset.']);
                        game._showPause.value = false;
                      },
                      child: const m.Text('Reset Progress')),
                  m.TextButton(
                      onPressed: () {
                        if (game._audioMuted) {
                          FlameAudio.bgm.resume();
                        } else {
                          FlameAudio.bgm.pause();
                        }
                        game._audioMuted = !game._audioMuted;
                        game._showPause.value = false;
                      },
                      child: m.Text(game._audioMuted ? 'Unmute Audio' : 'Mute Audio')),
                ],
              ),
            ),
          );
        },
      ),
      // Top-left hint when near interactables
      m.Positioned(
        left: 12,
        top: 12,
        child: m.ValueListenableBuilder<String?>(
          valueListenable: game.interactHint,
          builder: (context, value, _) {
            if (value == null) return const m.SizedBox.shrink();
            return m.Container(
              padding: const m.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: m.BoxDecoration(
                color: m.Colors.black.withOpacity(0.55),
                borderRadius: m.BorderRadius.circular(6),
              ),
              child: m.Text('A: Interact — ' + value, style: const m.TextStyle(color: m.Colors.white)),
            );
          },
        ),
      ),
      // Dialog box
      m.Positioned(
        left: 12,
        right: 12,
        bottom: 84,
        child: m.ValueListenableBuilder<_DialogLine?>(
          valueListenable: game.activeLine,
          builder: (context, line, _) {
            if (line == null) return const m.SizedBox.shrink();
            final portrait = _portraitFor(line.speaker);
            return m.Container(
              padding: const m.EdgeInsets.all(12),
              decoration: m.BoxDecoration(
                color: m.Colors.black.withOpacity(0.7),
                borderRadius: m.BorderRadius.circular(8),
                border: m.Border.all(color: m.Colors.white24),
              ),
              child: m.Row(crossAxisAlignment: m.CrossAxisAlignment.start, children: [
                if (portrait != null)
                  m.Container(
                    width: 64,
                    height: 64,
                    margin: const m.EdgeInsets.only(right: 12),
                    decoration: m.BoxDecoration(
                      borderRadius: m.BorderRadius.circular(6),
                      border: m.Border.all(color: m.Colors.white24),
                      image: m.DecorationImage(image: m.AssetImage(portrait), fit: m.BoxFit.cover),
                    ),
                  ),
                m.Expanded(
                  child: m.Column(
                    crossAxisAlignment: m.CrossAxisAlignment.start,
                    mainAxisSize: m.MainAxisSize.min,
                    children: [
                      m.Text(line.speaker, style: const m.TextStyle(color: m.Colors.amber, fontWeight: m.FontWeight.bold)),
                      const m.SizedBox(height: 6),
                      m.Text(line.text, style: const m.TextStyle(color: m.Colors.white)),
                      const m.SizedBox(height: 6),
                      const m.Text('Tap Action to continue', style: const m.TextStyle(color: m.Colors.white54, fontSize: 12)),
                    ],
                  ),
                ),
              ]),
            );
          },
        ),
      ),
      // Action (A) and Attack (B) buttons (bottom-right)
      m.Positioned(
        right: 24,
        bottom: 24,
        child: m.Row(
          mainAxisSize: m.MainAxisSize.min,
          children: [
            m.ElevatedButton(
              style: m.ButtonStyle(
                shape: m.MaterialStateProperty.all(const m.CircleBorder()),
                padding: m.MaterialStateProperty.all(const m.EdgeInsets.all(18)),
              ),
              onPressed: game.onActionPressed,
              child: const m.Text('A'),
            ),
            const m.SizedBox(width: 12),
            m.ElevatedButton(
              style: m.ButtonStyle(
                shape: m.MaterialStateProperty.all(const m.CircleBorder()),
                padding: m.MaterialStateProperty.all(const m.EdgeInsets.all(18)),
              ),
              onPressed: game.onAttackPressed,
              child: const m.Text('B'),
            ),
          ],
        ),
      ),
    ]);
  }
}
