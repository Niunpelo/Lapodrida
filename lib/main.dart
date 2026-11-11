import 'dart:convert';
import 'dart:math' show Random;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum Phase { bidding, results }

const Map<int, String> decks = {
  48: 'Española · 48',
  52: 'Francesa · 52',
};

int maxCardsFor(int players, int deckSize) {
  final m = deckSize ~/ players;
  return m < 1 ? 1 : m;
}

int totalRoundsFor(int maxCards) => 2 * maxCards - 1;

int roundPoints(int bid, int won) {
  if (bid == won) return 10 + 3 * bid;
  return -3 * (bid - won).abs();
}

class RoundRecord {
  RoundRecord(this.bids, this.won);

  final List<int> bids;
  final List<int> won;

  Map<String, dynamic> toJson() => {'bids': bids, 'won': won};

  factory RoundRecord.fromJson(Map<String, dynamic> j) => RoundRecord(
        (j['bids'] as List).cast<int>().toList(),
        (j['won'] as List).cast<int>().toList(),
      );
}

class Game {
  Game({
    required this.players,
    required this.deckSize,
    required this.maxCards,
    required this.firstDealer,
    List<RoundRecord>? rounds,
    List<int>? bids,
    List<int>? won,
    this.phase = Phase.bidding,
  })  : rounds = rounds ?? <RoundRecord>[],
        bids = bids ?? List<int>.filled(players.length, 0),
        won = won ?? List<int>.filled(players.length, 0);

  final List<String> players;
  final int deckSize;
  final int maxCards;
  final int firstDealer;

  final List<RoundRecord> rounds;

  List<int> bids;
  List<int> won;
  Phase phase;

  int get n => players.length;
  int get totalRounds => totalRoundsFor(maxCards);
  int get roundIndex => rounds.length;
  bool get finished => rounds.length >= totalRounds;

  int cardsForRound(int i) => i < maxCards ? i + 1 : 2 * maxCards - 1 - i;

  int get cards => cardsForRound(roundIndex);

  bool get allCardsDealt => cards * n == deckSize;

  String get roundKind {
    final i = roundIndex;
    if (i == maxCards - 1) return 'Ronda máxima';
    return i < maxCards - 1 ? 'Subida' : 'Bajada';
  }

  int get dealer => (firstDealer + roundIndex) % n;

  List<int> get bidOrder => [for (var k = 1; k <= n; k++) (dealer + k) % n];

  List<int> get totals {
    final t = List<int>.filled(n, 0);
    for (final r in rounds) {
      for (var i = 0; i < n; i++) {
        t[i] += roundPoints(r.bids[i], r.won[i]);
      }
    }
    return t;
  }

  int get bidSum => bids.fold(0, (a, b) => a + b);
  int get wonSum => won.fold(0, (a, b) => a + b);

  int? get forbiddenForDealer {
    var sum = 0;
    for (var i = 0; i < n; i++) {
      if (i != dealer) sum += bids[i];
    }
    final f = cards - sum;
    return (f >= 0 && f <= cards) ? f : null;
  }

  bool get bidsValid => forbiddenForDealer != bids[dealer];
  bool get resultsValid => wonSum == cards;

  void confirmBids() {
    phase = Phase.results;
  }

  void backToBids() {
    phase = Phase.bidding;
  }

  void finishRound() {
    rounds.add(RoundRecord(List<int>.of(bids), List<int>.of(won)));
    bids = List<int>.filled(n, 0);
    won = List<int>.filled(n, 0);
    phase = Phase.bidding;
  }

  void undoLastRound() {
    if (rounds.isEmpty) return;
    final r = rounds.removeLast();
    bids = List<int>.of(r.bids);
    won = List<int>.of(r.won);
    phase = Phase.results;
  }

  Map<String, dynamic> toJson() => {
        'players': players,
        'deckSize': deckSize,
        'maxCards': maxCards,
        'firstDealer': firstDealer,
        'rounds': rounds.map((r) => r.toJson()).toList(),
        'bids': bids,
        'won': won,
        'phase': phase.name,
      };

  factory Game.fromJson(Map<String, dynamic> j) => Game(
        players: (j['players'] as List).cast<String>().toList(),
        deckSize: j['deckSize'] as int,
        maxCards: j['maxCards'] as int,
        firstDealer: j['firstDealer'] as int,
        rounds: (j['rounds'] as List)
            .map((e) => RoundRecord.fromJson(e as Map<String, dynamic>))
            .toList(),
        bids: (j['bids'] as List).cast<int>().toList(),
        won: (j['won'] as List).cast<int>().toList(),
        phase: Phase.values.byName(j['phase'] as String),
      );
}

class GameStore extends ChangeNotifier {
  static const _key = 'podrida_game_v1';

  Game? game;
  SharedPreferences? _prefs;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_key);
    if (raw == null) return;
    try {
      game = Game.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      game = null;
    }
  }

  void start(Game g) {
    game = g;
    _save();
    notifyListeners();
  }

  void update(void Function(Game x) change) {
    final g = game;
    if (g == null) return;
    change(g);
    _save();
    notifyListeners();
  }

  void clear() {
    game = null;
    _prefs?.remove(_key);
    notifyListeners();
  }

  void _save() {
    final g = game;
    if (g == null) return;
    _prefs?.setString(_key, jsonEncode(g.toJson()));
  }
}

final GameStore store = GameStore();

class NumberStepper extends StatelessWidget {
  const NumberStepper({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleLarge;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 40,
          child: Text('$value', textAlign: TextAlign.center, style: style),
        ),
        IconButton.filledTonal(
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

String fmtPts(int v) => v > 0 ? '+$v' : '$v';

Color ptsColor(BuildContext context, int v) {
  final cs = Theme.of(context).colorScheme;
  return v >= 0 ? cs.primary : cs.error;
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(c).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(c).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
  return r ?? false;
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _newGame(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SetupScreen()),
    );
  }

  void _continue(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const GameScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ListenableBuilder(
            listenable: store,
            builder: (context, _) {
              final g = store.game;
              final continueLabel = g == null
                  ? ''
                  : (g.finished
                      ? 'Ver resultado'
                      : 'Continuar · ronda ${g.roundIndex + 1} de ${g.totalRounds}');

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  Icon(Icons.style_outlined, size: 56, color: cs.primary),
                  const SizedBox(height: 16),
                  Text(
                    'La Podrida',
                    style: t.textTheme.displaySmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Turnos y puntos para jugar con cartas de verdad.',
                    style: t.textTheme.bodyLarge
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const Spacer(),
                  if (g != null) ...[
                    FilledButton(
                      onPressed: () => _continue(context),
                      child: Text(continueLabel),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => _newGame(context),
                      child: const Text('Nueva partida'),
                    ),
                  ] else
                    FilledButton(
                      onPressed: () => _newGame(context),
                      child: const Text('Nueva partida'),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  int _players = 4;
  int _deck = 48;
  int? _maxOverride;

  int get _autoMax => maxCardsFor(_players, _deck);

  int get _maxCards {
    final m = _maxOverride ?? _autoMax;
    if (m > _autoMax) return _autoMax;
    if (m < 1) return 1;
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final maxC = _maxCards;
    final total = totalRoundsFor(maxC);

    return Scaffold(
      appBar: AppBar(title: const Text('Nueva partida')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  children: [
                    const _Label('¿Cuántos jugáis?'),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$_players jugadores',
                            style: t.textTheme.headlineSmall,
                          ),
                        ),
                        NumberStepper(
                          value: _players,
                          min: 3,
                          max: 10,
                          onChanged: (v) => setState(() {
                            _players = v;
                            _maxOverride = null;
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    const _Label('¿Con qué baraja?'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final e in decks.entries)
                          ChoiceChip(
                            label: Text(e.value),
                            selected: _deck == e.key,
                            onSelected: (_) => setState(() {
                              _deck = e.key;
                              _maxOverride = null;
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$total rondas',
                            style: t.textTheme.headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$maxC de subida y ${maxC - 1} de bajada\n'
                            'De 1 a $maxC cartas por jugador',
                            style: t.textTheme.bodyMedium
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Expanded(child: Text('Máximo de cartas')),
                              NumberStepper(
                                value: maxC,
                                min: 1,
                                max: _autoMax,
                                onChanged: (v) =>
                                    setState(() => _maxOverride = v),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => NamesScreen(
                        players: _players,
                        deckSize: _deck,
                        maxCards: maxC,
                      ),
                    ),
                  );
                },
                child: const Text('Siguiente'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: t.textTheme.titleMedium
            ?.copyWith(color: t.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class NamesScreen extends StatefulWidget {
  const NamesScreen({
    super.key,
    required this.players,
    required this.deckSize,
    required this.maxCards,
  });

  final int players;
  final int deckSize;
  final int maxCards;

  @override
  State<NamesScreen> createState() => _NamesScreenState();
}

class _NamesScreenState extends State<NamesScreen> {
  late final List<TextEditingController> _ctrls = List.generate(
    widget.players,
    (_) => TextEditingController(),
  );

  int? _dealer;
  int? _highlight;
  bool _drawing = false;

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  String _name(int i) {
    final s = _ctrls[i].text.trim();
    return s.isEmpty ? 'Jugador ${i + 1}' : s;
  }

  Future<void> _draw() async {
    if (_drawing) return;
    FocusScope.of(context).unfocus();

    final n = widget.players;
    final winner = Random().nextInt(n);
    const steps = 16;

    setState(() {
      _drawing = true;
      _dealer = null;
    });

    for (var i = 0; i < steps; i++) {
      if (!mounted) return;
      setState(() => _highlight = (winner - (steps - 1 - i)) % n);
      await Future<void>.delayed(Duration(milliseconds: 70 + i * 14));
    }

    if (!mounted) return;
    setState(() {
      _drawing = false;
      _dealer = winner;
      _highlight = null;
    });
  }

  void _start() {
    final dealer = _dealer;
    if (dealer == null) return;
    final names = [for (var i = 0; i < widget.players; i++) _name(i)];
    store.start(
      Game(
        players: names,
        deckSize: widget.deckSize,
        maxCards: widget.maxCards,
        firstDealer: dealer,
      ),
    );
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const GameScreen()),
      (route) => route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final n = widget.players;
    final dealer = _dealer;

    return Scaffold(
      appBar: AppBar(title: const Text('Jugadores')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Escribe los nombres en el orden en que estáis sentados. '
                'El reparto irá pasando al siguiente de la lista.',
                style: t.textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  itemCount: n,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final isDealer = !_drawing && dealer == i;
                    final active = _highlight == i || isDealer;
                    return TextField(
                      controller: _ctrls[i],
                      enabled: !_drawing,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: i == n - 1
                          ? TextInputAction.done
                          : TextInputAction.next,
                      onChanged: (_) {
                        if (_dealer != null) setState(() {});
                      },
                      decoration: InputDecoration(
                        labelText: 'Jugador ${i + 1}',
                        filled: active,
                        fillColor: active ? cs.primaryContainer : null,
                        suffixIcon: isDealer
                            ? Icon(Icons.style, color: cs.primary)
                            : null,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              if (dealer != null && !_drawing)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Reparte primero ${_name(dealer)}',
                    textAlign: TextAlign.center,
                    style: t.textTheme.titleMedium,
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _drawing ? null : _draw,
                icon: const Icon(Icons.shuffle),
                label: Text(
                  dealer == null ? 'Sortear quién reparte' : 'Sortear de nuevo',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: (dealer == null || _drawing) ? null : _start,
                child: const Text('Empezar partida'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GameScreen extends StatelessWidget {
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final g = store.game;
        if (g == null) return const Scaffold();
        return g.finished ? FinalView(game: g) : RoundView(game: g);
      },
    );
  }
}

void _openScoreboard(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const ScoreboardScreen()),
  );
}

class RoundView extends StatelessWidget {
  const RoundView({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final g = game;
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final bidding = g.phase == Phase.bidding;
    final cards = g.cards;
    final cardsLabel = cards == 1 ? 'carta' : 'cartas';
    final dealerName = g.players[g.dealer];
    final order = g.bidOrder;
    final totals = g.totals;
    final isLastRound = g.roundIndex == g.totalRounds - 1;

    final rows = <Widget>[];
    for (var k = 0; k < order.length; k++) {
      final p = order[k];
      final isDealer = p == g.dealer;

      InlineSpan subtitle;
      if (bidding) {
        final tag = isDealer ? ' · reparte' : '';
        subtitle = TextSpan(text: '${totals[p]} pts$tag');
      } else {
        final pts = roundPoints(g.bids[p], g.won[p]);
        subtitle = TextSpan(
          text: 'Pidió ${g.bids[p]} · ',
          children: [
            TextSpan(
              text: '${fmtPts(pts)} pts',
              style: TextStyle(
                color: ptsColor(context, pts),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
      }

      rows.add(
        _PlayerRow(
          position: k + 1,
          name: g.players[p],
          isDealer: isDealer,
          subtitle: subtitle,
          value: bidding ? g.bids[p] : g.won[p],
          max: cards,
          onChanged: (v) => store.update((x) {
            if (bidding) {
              x.bids[p] = v;
            } else {
              x.won[p] = v;
            }
          }),
        ),
      );
    }

    final List<Widget> footer;
    if (bidding) {
      final f = g.forbiddenForDealer;
      final bad = !g.bidsValid;
      footer = [
        Text(
          'Apuestas: ${g.bidSum} de $cards',
          style: t.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        if (f != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '$dealerName reparte y no puede pedir $f',
              style: t.textTheme.bodyMedium?.copyWith(
                color: bad ? cs.error : cs.onSurfaceVariant,
                fontWeight: bad ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed:
              bad ? null : () => store.update((x) => x.confirmBids()),
          child: const Text('Empezar ronda'),
        ),
      ];
    } else {
      final ok = g.resultsValid;
      footer = [
        Text(
          ok
              ? 'Bazas: ${g.wonSum} de $cards'
              : 'Bazas: ${g.wonSum} de $cards · tienen que sumar $cards',
          style: t.textTheme.bodyMedium?.copyWith(
            color: ok ? cs.onSurfaceVariant : cs.error,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: ok ? () => store.update((x) => x.finishRound()) : null,
          child: Text(isLastRound ? 'Anotar y ver resultado' : 'Anotar ronda'),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: () => store.update((x) => x.backToBids()),
          child: const Text('Corregir apuestas'),
        ),
      ];
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Ronda ${g.roundIndex + 1} de ${g.totalRounds}'),
        actions: [
          IconButton(
            tooltip: 'Puntuaciones',
            icon: const Icon(Icons.leaderboard_outlined),
            onPressed: () => _openScoreboard(context),
          ),
          _GameMenu(game: g),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$cards $cardsLabel',
                          style: t.textTheme.displaySmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${g.roundKind} · reparte $dealerName',
                          style: t.textTheme.bodyLarge
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        if (g.allCardsDealt)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Se reparten todas las cartas: la última se enseña.',
                              style: t.textTheme.bodyMedium
                                  ?.copyWith(color: cs.primary),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  bidding
                      ? 'Apuestas, por orden · empieza ${g.players[order.first]}'
                      : 'Bazas ganadas · apunta cuántas ha hecho cada uno',
                  style: t.textTheme.titleSmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                children: rows,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: footer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.position,
    required this.name,
    required this.isDealer,
    required this.subtitle,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final int position;
  final String name;
  final bool isDealer;
  final InlineSpan subtitle;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: isDealer ? cs.primary : cs.surfaceContainerHighest,
            foregroundColor: isDealer ? cs.onPrimary : cs.onSurfaceVariant,
            child: Text('$position', style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.titleMedium,
                ),
                Text.rich(
                  subtitle,
                  style: t.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          NumberStepper(
            value: value,
            min: 0,
            max: max,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _GameMenu extends StatelessWidget {
  const _GameMenu({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (value) async {
        if (value == 'undo') {
          store.update((x) => x.undoLastRound());
        } else if (value == 'end') {
          final ok = await confirmDialog(
            context,
            title: 'Terminar partida',
            message: 'Se borrará la partida en curso.',
            action: 'Terminar',
          );
          if (ok && context.mounted) {
            store.clear();
            Navigator.of(context).popUntil((r) => r.isFirst);
          }
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: 'undo',
          enabled: game.rounds.isNotEmpty,
          child: const Text('Deshacer última ronda'),
        ),
        const PopupMenuItem<String>(
          value: 'end',
          child: Text('Terminar partida'),
        ),
      ],
    );
  }
}

class FinalView extends StatelessWidget {
  const FinalView({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final g = game;
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final totals = g.totals;

    final order = List<int>.generate(g.n, (i) => i)
      ..sort((a, b) => totals[b].compareTo(totals[a]));
    final best = totals.reduce((a, b) => a > b ? a : b);
    final winners = [
      for (var i = 0; i < g.n; i++)
        if (totals[i] == best) g.players[i],
    ];
    final joined = winners.join(' y ');
    final title = winners.length == 1 ? 'Gana $joined' : 'Empate: $joined';

    int rankOf(int idx) => 1 + totals.where((x) => x > totals[idx]).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fin de la partida'),
        actions: [_GameMenu(game: g)],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: t.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: [
                    for (final p in order)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 36,
                              child: Text(
                                '${rankOf(p)}º',
                                style: t.textTheme.titleMedium
                                    ?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                g.players[p],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.textTheme.titleMedium?.copyWith(
                                  fontWeight: rankOf(p) == 1
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                            Text(
                              '${totals[p]} pts',
                              style: t.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: ptsColor(context, totals[p]),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => _openScoreboard(context),
                child: const Text('Ver todas las puntuaciones'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  store.clear();
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute<void>(
                      builder: (_) => const SetupScreen(),
                    ),
                    (route) => route.isFirst,
                  );
                },
                child: const Text('Nueva partida'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ScoreboardScreen extends StatelessWidget {
  const ScoreboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Puntuaciones')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final g = store.game;
            if (g == null) return const SizedBox.shrink();
            return _Table(game: g);
          },
        ),
      ),
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.game});

  final Game game;

  DataRow _roundRow(BuildContext context, int r) {
    final t = Theme.of(context);
    final small = t.textTheme.bodySmall
        ?.copyWith(color: t.colorScheme.onSurfaceVariant);
    final rec = game.rounds[r];
    final c = game.cardsForRound(r);
    final cardsLabel = c == 1 ? 'carta' : 'cartas';

    return DataRow(
      cells: [
        DataCell(
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ronda ${r + 1}'),
              Text('$c $cardsLabel', style: small),
            ],
          ),
        ),
        for (var i = 0; i < game.n; i++)
          DataCell(
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  fmtPts(roundPoints(rec.bids[i], rec.won[i])),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: ptsColor(
                      context,
                      roundPoints(rec.bids[i], rec.won[i]),
                    ),
                  ),
                ),
                Text(
                  'pidió ${rec.bids[i]} · hizo ${rec.won[i]}',
                  style: small,
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = game;
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final totals = g.totals;

    final columns = <DataColumn>[
      const DataColumn(label: Text('')),
      for (final name in g.players)
        DataColumn(
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 90),
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
    ];

    final rows = <DataRow>[
      DataRow(
        cells: [
          DataCell(
            Text(
              'Total',
              style: t.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          for (var i = 0; i < g.n; i++)
            DataCell(
              Text(
                '${totals[i]}',
                style: t.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: ptsColor(context, totals[i]),
                ),
              ),
            ),
        ],
      ),
      for (var r = 0; r < g.rounds.length; r++) _roundRow(context, r),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (g.rounds.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            child: Text(
              'Todavía no hay rondas anotadas.',
              style: t.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 20,
                columns: columns,
                rows: rows,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await store.load();
  runApp(const PodridaApp());
}

class PodridaApp extends StatelessWidget {
  const PodridaApp({super.key});

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2E6B4F),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'La Podrida',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const HomeScreen(),
    );
  }
}
