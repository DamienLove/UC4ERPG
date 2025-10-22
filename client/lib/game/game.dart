import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flame/collisions.dart';
import 'package:flame/sprite.dart';
import 'package:flame_tiled/flame_tiled.dart';
import 'package:flutter/material.dart' as m;
import 'package:flutter/foundation.dart' as f show ValueNotifier;
import 'dart:math' as math;
import 'state.dart';

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

  @override
  Future<void> onLoad() async {
    // Normalize Flame image prefix so asset keys start with 'assets/'
    images.prefix = 'assets/';
    // Load tileset
    final labTilesImage = await images.load('tilesets/lab_tiles.png');
    _labTiles = SpriteSheet(image: labTilesImage, srcSize: Vector2.all(32));

    try {
      _tiled = await TiledComponent.load('maps/lab.tmx', Vector2.all(32));
      add(_tiled!);

      // Collisions from object layer
      final collisions = _tiled!.tileMap.getLayer<ObjectGroup>('collisions');
      if (collisions != null) {
        for (final obj in collisions.objects) {
          add(Wall(rect: Rect.fromLTWH(obj.x, obj.y, obj.width, obj.height)));
        }
      }

      // Spawns
      Vector2 playerPos = Vector2.zero();
      Vector2 elenaPos = Vector2(520, 340);
      Vector2 arunPos = Vector2(440, 300);
      Vector2 consentPos = Vector2(260, 480);
      final spawns = _tiled!.tileMap.getLayer<ObjectGroup>('spawns');
      if (spawns != null) {
        for (final o in spawns.objects) {
          final v = Vector2(o.x + (o.width / 2), o.y + (o.height / 2));
          switch (o.name) {
            case 'player': playerPos = v; break;
            case 'doc_elena': elenaPos = v; break;
            case 'doc_arun': arunPos = v; break;
            case 'consent_console': consentPos = v; break;
            case 'door_to_corridor':
              add(Door(position: v, label: 'To Corridor', targetScene: 'corridor', lockedUntilConsent: true));
              break;
          }
        }
      }

      // Player + camera
      // NOTE: Using placeholder sprites, change getSprite(row, col) to match your tileset
      _player = Player(position: playerPos, sprite: _labTiles.getSprite(0, 1)); // Player sprite
      add(_player);
      camera.follow(_player);

      // Doctors and console
      addAll([
        DoctorNPC(name: 'Dr. Elena Vega', position: elenaPos, lines: const [
          'Vitals are steady. The fungal lattice is responsive.',
          'When you are ready, we will proceed — your consent matters.',
        ], sprite: _labTiles.getSprite(0, 2)), // Dr. Elena sprite
        DoctorNPC(name: 'Dr. Arun Patel', position: arunPos, lines: const [
          'Welcome. You are safe — take a slow breath.',
          'We are stabilizing the interface to the bio-compute mesh.',
        ], sprite: _labTiles.getSprite(0, 3)), // Dr. Arun sprite
        ConsentConsole(position: consentPos),
      ]);
    } catch (_) {
      // Fallback background
      add(Background());
      // Fallback room bounds
      addAll([
        Wall(rect: const Rect.fromLTWH(-500, -300, 1000, 20)),
        Wall(rect: const Rect.fromLTWH(-500, 280, 1000, 20)),
        Wall(rect: const Rect.fromLTWH(-500, -300, 20, 600)),
        Wall(rect: const Rect.fromLTWH(480, -300, 20, 600)),
      ]);
      // Fallback props
      addAll([
        HologramPanel(position: Vector2(-320, -180), size: Vector2(180, 100)),
        HologramPanel(position: Vector2(-120, -180), size: Vector2(180, 100)),
        ConsoleStation(position: Vector2(-380, 0)),
        ConsoleStation(position: Vector2(420, -40)),
        FungusVat(position: Vector2(120, -60)),
        FungusVat(position: Vector2(220, 30)),
        BioRack(position: Vector2(-40, 120)),
      ]);
      // Fallback player + camera
      _player = Player(position: Vector2(-200, 0), sprite: _labTiles.getSprite(0, 1));
      add(_player);
      camera.follow(_player);
      // Fallback doctors and console
      addAll([
        DoctorNPC(name: 'Dr. Elena Vega', position: Vector2(160, 40), lines: const [
          'Vitals are steady. The fungal lattice is responsive.',
          'When you are ready, we will proceed — your consent matters.',
        ], sprite: _labTiles.getSprite(0, 2)),
        DoctorNPC(name: 'Dr. Arun Patel', position: Vector2(80, 0), lines: const [
          'Welcome. You are safe — take a slow breath.',
          'We are stabilizing the interface to the bio-compute mesh.',
        ], sprite: _labTiles.getSprite(0, 3)),
        ConsentConsole(position: Vector2(-200, 120)),
      ]);
    }

    // Joystick (bottom-left)
    _joystick = JoystickComponent(
      knob: CircleComponent(radius: 22, paint: Paint()..color = m.Colors.indigo),
      background: CircleComponent(radius: 44, paint: Paint()..color = m.Colors.indigo.withOpacity(0.2)),
      margin: const m.EdgeInsets.only(left: 24, bottom: 24),
    );
    add(_joystick);

    // Show HUD overlay
    overlays.add('HUD');
  }

  @override
  void update(double dt) {
    super.update(dt);
    // Drive player with joystick unless in dialog
    if (!_inDialog) {
      final delta = _joystick.delta;
      _player.move(delta, dt);
    }

    // Update interact hint
    if (!_inDialog) {
      final target = _nearestInteractable();
      interactHint.value = target?.$2; // label
    } else {
      interactHint.value = null;
    }

    // Keep joystick anchored to screen bottom-left when camera moves
    // Estimated placement using camera center and current viewport size
    final halfW = size.x / 2;
    final halfH = size.y / 2;
    final joyOffset = Vector2(24 + 44, 24 + 44); // margin + radius
    _joystick.position = Vector2(
      camera.viewfinder.position.x - halfW + joyOffset.x,
      camera.viewfinder.position.y + halfH - joyOffset.y,
    );
  }

  // Called from HUD Action button
  void onActionPressed() {
    if (_inDialog) {
      _advanceDialog();
      return;
    }
    // Find closest interactable (NPC or object)
    final nearest = _nearestInteractable();
    if (nearest != null) {
      final kind = nearest.$1;
      if (kind is DoctorNPC) {
        _markSpoken(kind.name);
        _startDialog(kind.name, kind.lines);
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

  // returns (component, label)
  (Object, String)? _nearestInteractable() {
    Object? nearest;
    String? label;
    double best = 84; // px
    for (final c in children) {
      if (c is DoctorNPC) {
        final d = _player.position.distanceTo(c.position);
        if (d < best) { best = d; nearest = c; label = c.name; }
      } else if (c is Inspectable) {
        final d = _player.position.distanceTo(c.position);
        if (d < best) { best = d; nearest = c; label = c.label; }
      }
    }
    if (nearest == null || label == null) return null;
    return (nearest!, label!);
  }

  void _startDialog(String speaker, List<String> lines) {
    _dialogQueue
      ..clear()
      ..addAll(lines.map((t) => _DialogLine(speaker: speaker, text: t)));
    _inDialog = true;
    _advanceDialog();
  }

  void _advanceDialog() {
    if (_dialogQueue.isEmpty) {
      _inDialog = false;
      activeLine.value = null;
      return;
    }
    activeLine.value = _dialogQueue.removeAt(0);
  }

  void _markSpoken(String name) {
    _spokenTo.add(name);
    gs.markSpoken(name);
    if (_spokenTo.contains('Dr. Elena Vega') && _spokenTo.contains('Dr. Arun Patel')) {
      objective.value = 'Objective: Approach the Consent Console (A to consent)';
    }
  }

  void _presentConsent() {
    _inDialog = false;
    activeLine.value = null;
    _showConsent.value = true;
  }

  void onConsentChoice(bool consented) {
    _showConsent.value = false;
    if (consented) {
      objective.value = 'Consent recorded. Calibration starting…';
      gs.setConsent(true);
      _startDialog('System', const [
        'Consent acknowledged. Initializing calibration sequence.',
        'Hold steady � establishing cognitive link to bio-compute lattice.',
      ]);
      // Optional: record to in-app journal for later sync
      // (kept internal to avoid importing state here)
    } else {
      _startDialog('System', const [
        'Consent deferred. You may speak to the doctors again or proceed later.',
      ]);
      objective.value = 'Objective: Speak with Dr. Vega/Dr. Patel or consent when ready.';
    }
  }
  
  void _tryTransition(Door door) {
    if (door.lockedUntilConsent && !gs.consentGiven.value) {
      _startDialog('Door', const ['Locked. Consent required to proceed.']);
      return;
    }
    _loadScene(door.targetScene);
  }

  Future<void> _loadScene(String scene) async {
    // Remove previous scene components (map, props, NPCs, doors, walls)
    final toRemove = children.where((c) =>
        c is TiledComponent ||
        c is Wall ||
        c is DoctorNPC ||
        c is HologramPanel ||
        c is ConsoleStation ||
        c is FungusVat ||
        c is BioRack ||
        c is ConsentConsole ||
        c is Door).toList();
    for (final c in toRemove) {
      c.removeFromParent();
    }

    // Load TMX for the scene
    final mapPath = scene == 'lab' ? 'maps/lab.tmx' : 'maps/corridor.tmx';
    _tiled = await TiledComponent.load(mapPath, Vector2.all(32));
    add(_tiled!);

    // Collisions
    final collisions = _tiled!.tileMap.getLayer<ObjectGroup>('collisions');
    if (collisions != null) {
      for (final obj in collisions.objects) {
        add(Wall(rect: Rect.fromLTWH(obj.x, obj.y, obj.width, obj.height)));
      }
    }

    // Spawns and objects
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
            add(DoctorNPC(name: 'Dr. Elena Vega', position: v, lines: const [
              'Vitals are steady. The fungal lattice is responsive.',
              'When you are ready, we will proceed — your consent matters.',
            ], sprite: _labTiles.getSprite(0, 2)));
            break;
          case 'doc_arun':
            add(DoctorNPC(name: 'Dr. Arun Patel', position: v, lines: const [
              'Welcome. You are safe — take a slow breath.',
              'We are stabilizing the interface to the bio-compute mesh.',
            ], sprite: _labTiles.getSprite(0, 3)));
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
        }
      }
    }

    _player.position = playerPos;
    camera.follow(_player);
    gs.section.value = scene == 'lab' ? "Doctors' Lab" : 'Corridor';
  }
}

class Background extends PositionComponent {
  Background() : super(priority: -10);
  @override
  void render(Canvas canvas) {
    final size = canvas.getLocalClipBounds().size;
    final paint = Paint()..color = m.Colors.grey.shade900;
    canvas.drawRect(Rect.fromLTWH(-5000, -5000, 10000, 10000), paint);
    // Simple grid for sense of scale
    final grid = Paint()
      ..color = m.Colors.white12
      ..strokeWidth = 1;
    for (double x = -5000; x <= 5000; x += 64) {
      canvas.drawLine(Offset(x, -5000), Offset(x, 5000), grid);
    }
    for (double y = -5000; y <= 5000; y += 64) {
      canvas.drawLine(Offset(-5000, y), Offset(5000, y), grid);
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

class Player extends SpriteComponent with CollisionCallbacks {
  final double speed = 220; // units per second

  Player({required Vector2 position, required Sprite sprite})
      : super(sprite: sprite, position: position) {
    size = Vector2.all(40);
    anchor = Anchor.center;
  }

  @override
  Future<void> onLoad() async {
    add(RectangleHitbox());
  }

  void move(Vector2 input, double dt) {
    if (input.length2 == 0) return;
    final dir = input.normalized();
    final next = position + dir * speed * dt;
    position = next;
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
  HologramPanel({required super.position, required super.size}) { anchor = Anchor.topLeft; }
  @override
  void update(double dt) { _t += dt; }
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
  ConsoleStation({required super.position}) { size = Vector2(48, 36); anchor = Anchor.center; }
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
  FungusVat({required super.position}) { size = Vector2(64, 96); anchor = Anchor.center; }
  @override
  void render(Canvas canvas) {.
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
  BioRack({required super.position}) { size = Vector2(120, 32); anchor = Anchor.center; }
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
  ConsentConsole({required super.position}) { size = Vector2(60, 44); anchor = Anchor.center; }
  @override
  void render(Canvas canvas) {
    final base = Paint()..color = m.Colors.blueGrey.shade800;
    canvas.drawRRect(RRect.fromRectAndRadius(size.toRect(), const Radius.circular(8)), base);
    final screen = Paint()..color = m.Colors.tealAccent.withOpacity(0.85);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(6, 6, size.x - 12, size.y - 16), const Radius.circular(6)), screen);
    final btn = Paint()..color = m.Colors.greenAccent;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.x/2 - 10, size.y - 14, 20, 8), const Radius.circular(3)), btn);
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

class _DialogLine {
  final String speaker;
  final String text;
  _DialogLine({required this.speaker, required this.text});
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
  @override
  m.Widget build(m.BuildContext context) {
    return m.Stack(children: [
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
                  builder: (context, ch, _) => m.Text(ch, style: const m.TextStyle(color: m.Colors.white, fontWeight: m.FontWeight.bold)),
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
                              m.Icon(item.complete ? m.Icons.check_circle : m.Icons.radio_button_unchecked, size: 16, color: item.complete ? m.Colors.greenAccent : m.Colors.white38),
                              const m.SizedBox(width: 6),
                              m.Text(item.text, style: const m.TextStyle(color: m.Colors.white)),
                            ],
                          )
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
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
              child: m.Text('A: Interact – ' + value, style: const m.TextStyle(color: m.Colors.white)),
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
            return m.Container(
              padding: const m.EdgeInsets.all(12),
              decoration: m.BoxDecoration(
                color: m.Colors.black.withOpacity(0.7),
                borderRadius: m.BorderRadius.circular(8),
                border: m.Border.all(color: m.Colors.white24),
              ),
              child: m.Column(
                crossAxisAlignment: m.CrossAxisAlignment.start,
                mainAxisSize: m.MainAxisSize.min,
                children: [
                  m.Text(line.speaker, style: const m.TextStyle(color: m.Colors.amber, fontWeight: m.FontWeight.bold)),
                  const m.SizedBox(height: 6),
                  m.Text(line.text, style: const m.TextStyle(color: m.Colors.white)),
                  const m.SizedBox(height: 6),
                  const m.Text('Tap Action to continue', style: m.TextStyle(color: m.Colors.white54, fontSize: 12)),
                ],
              ),
            );
          },
        ),
      ),
      // Action button (bottom-right)
      m.Positioned(
        right: 24,
        bottom: 24,
        child: m.ElevatedButton(
          style: m.ElevatedButton.styleFrom(
            shape: const m.CircleBorder(),
            padding: const m.EdgeInsets.all(18),
          ),
          onPressed: game.onActionPressed,
          child: const m.Text('A'),
        ),
      ),
    ]);
  }
}


