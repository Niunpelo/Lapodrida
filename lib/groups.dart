import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart';

String plural(int n, String one, String many) => n == 1 ? '$n $one' : '$n $many';

String fmtDate(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

class GameRecord {
  GameRecord({
    required this.id,
    required this.date,
    required this.deckSize,
    required this.rounds,
    required this.players,
    required this.totals,
  });

  final String id;
  final DateTime date;
  final int deckSize;
  final int rounds;
  final List<String> players;
  final List<int> totals;

  int rankOf(int i) => 1 + totals.where((x) => x > totals[i]).length;

  List<int> get order => List<int>.generate(players.length, (i) => i)
    ..sort((a, b) => totals[b].compareTo(totals[a]));

  List<String> get winners => [
        for (var i = 0; i < players.length; i++)
          if (rankOf(i) == 1) players[i],
      ];

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'deckSize': deckSize,
        'rounds': rounds,
        'players': players,
        'totals': totals,
      };

  factory GameRecord.fromJson(Map<String, dynamic> j) => GameRecord(
        id: j['id'] as String,
        date: DateTime.parse(j['date'] as String),
        deckSize: j['deckSize'] as int,
        rounds: j['rounds'] as int,
        players: (j['players'] as List).cast<String>().toList(),
        totals: (j['totals'] as List).cast<int>().toList(),
      );
}

class PlayerStats {
  PlayerStats(this.name);

  final String name;
  int games = 0;
  int wins = 0;
  int points = 0;
}

class PlayGroup {
  PlayGroup({
    required this.id,
    required this.name,
    required this.members,
    List<GameRecord>? history,
  }) : history = history ?? <GameRecord>[];

  final String id;
  String name;

  List<String> members;
  final List<GameRecord> history;

  List<PlayerStats> get stats {
    final map = <String, PlayerStats>{};
    for (final g in history) {
      for (var i = 0; i < g.players.length; i++) {
        final s = map.putIfAbsent(g.players[i], () => PlayerStats(g.players[i]));
        s.games += 1;
        s.points += g.totals[i];
        if (g.rankOf(i) == 1) s.wins += 1;
      }
    }
    final list = map.values.toList();
    list.sort((a, b) {
      final w = b.wins.compareTo(a.wins);
      if (w != 0) return w;
      return b.points.compareTo(a.points);
    });
    return list;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'members': members,
        'history': history.map((r) => r.toJson()).toList(),
      };

  factory PlayGroup.fromJson(Map<String, dynamic> j) => PlayGroup(
        id: j['id'] as String,
        name: j['name'] as String,
        members: (j['members'] as List).cast<String>().toList(),
        history: (j['history'] as List)
            .map((e) => GameRecord.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class GroupsStore extends ChangeNotifier {
  static const _key = 'podrida_groups_v1';

  final List<PlayGroup> groups = [];
  SharedPreferences? _prefs;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_key);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List;
      groups.clear();
      for (final e in list) {
        groups.add(PlayGroup.fromJson(e as Map<String, dynamic>));
      }
    } catch (_) {
      groups.clear();
    }
  }

  PlayGroup? byId(String? id) {
    if (id == null) return null;
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  void _changed() {
    _prefs?.setString(
      _key,
      jsonEncode(groups.map((g) => g.toJson()).toList()),
    );
    notifyListeners();
  }

  PlayGroup create(String name, List<String> members) {
    final g = PlayGroup(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      members: members,
    );
    groups.add(g);
    _changed();
    return g;
  }

  void save() => _changed();

  void delete(String id) {
    groups.removeWhere((g) => g.id == id);
    _changed();
  }

  void upsertGame(String groupId, GameRecord r) {
    final g = byId(groupId);
    if (g == null) return;
    final i = g.history.indexWhere((x) => x.id == r.id);
    if (i >= 0) {
      g.history[i] = r;
    } else {
      g.history.add(r);
    }
    _changed();
  }

  void removeGame(String groupId, String gameId) {
    final g = byId(groupId);
    if (g == null) return;
    final before = g.history.length;
    g.history.removeWhere((x) => x.id == gameId);
    if (g.history.length != before) _changed();
  }
}

final GroupsStore groupStore = GroupsStore();

class GroupsScreen extends StatelessWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Grupos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const GroupEditScreen()),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Nuevo grupo'),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: groupStore,
          builder: (context, _) {
            final list = groupStore.groups;
            if (list.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Todavía no tienes grupos.\n'
                    'Crea uno para guardar el historial de vuestras partidas.',
                    textAlign: TextAlign.center,
                    style: t.textTheme.bodyLarge
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 96),
              children: [
                for (final g in list)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(g.name, style: t.textTheme.titleMedium),
                    subtitle: Text(
                      '${plural(g.members.length, 'jugador', 'jugadores')} · '
                      '${plural(g.history.length, 'partida', 'partidas')}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => GroupDetailScreen(groupId: g.id),
                        ),
                      );
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class GroupEditScreen extends StatefulWidget {
  const GroupEditScreen({super.key, this.group});

  final PlayGroup? group;

  @override
  State<GroupEditScreen> createState() => _GroupEditScreenState();
}

class _GroupEditScreenState extends State<GroupEditScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.group?.name ?? '');
  final List<TextEditingController> _members = [];
  final List<TextEditingController> _discarded = [];

  @override
  void initState() {
    super.initState();
    final existing = widget.group?.members ?? const <String>[];
    if (existing.isEmpty) {
      for (var i = 0; i < 4; i++) {
        _members.add(TextEditingController());
      }
    } else {
      for (final m in existing) {
        _members.add(TextEditingController(text: m));
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    for (final c in _members) {
      c.dispose();
    }
    for (final c in _discarded) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> get _names => [
        for (final c in _members)
          if (c.text.trim().isNotEmpty) c.text.trim(),
      ];

  String? get _problem {
    if (_name.text.trim().isEmpty) return 'Ponle un nombre al grupo.';
    final names = _names;
    if (names.length < 3) return 'Hacen falta al menos 3 jugadores.';
    final lower = names.map((n) => n.toLowerCase()).toSet();
    if (lower.length != names.length) return 'Hay nombres repetidos.';
    return null;
  }

  void _save() {
    final names = _names;
    final g = widget.group;
    if (g == null) {
      groupStore.create(_name.text.trim(), names);
    } else {
      g.name = _name.text.trim();
      g.members = names;
      groupStore.save();
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final problem = _problem;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.group == null ? 'Nuevo grupo' : 'Editar grupo'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nombre del grupo'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 20),
              Text(
                'Jugadores, en el orden de la mesa',
                style: t.textTheme.titleSmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: [
                    for (var i = 0; i < _members.length; i++)
                      Padding(
                        key: ObjectKey(_members[i]),
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _members[i],
                                textCapitalization: TextCapitalization.words,
                                decoration: InputDecoration(
                                  labelText: 'Jugador ${i + 1}',
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Quitar',
                              icon: const Icon(Icons.close),
                              onPressed: _members.length > 1
                                  ? () => setState(() {
                                        _discarded.add(_members.removeAt(i));
                                      })
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _members.length < 12
                            ? () => setState(() {
                                  _members.add(TextEditingController());
                                })
                            : null,
                        icon: const Icon(Icons.add),
                        label: const Text('Añadir jugador'),
                      ),
                    ),
                  ],
                ),
              ),
              if (problem != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Text(
                    problem,
                    style: t.textTheme.bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              const SizedBox(height: 4),
              FilledButton(
                onPressed: problem == null ? _save : null,
                child: const Text('Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GroupDetailScreen extends StatelessWidget {
  const GroupDetailScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: groupStore,
      builder: (context, _) {
        final g = groupStore.byId(groupId);
        if (g == null) return const Scaffold();
        return _GroupDetail(group: g);
      },
    );
  }
}

class _GroupDetail extends StatelessWidget {
  const _GroupDetail({required this.group});

  final PlayGroup group;

  @override
  Widget build(BuildContext context) {
    final g = group;
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final stats = g.stats;
    final games = List<GameRecord>.of(g.history)
      ..sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      appBar: AppBar(
        title: Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'edit') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => GroupEditScreen(group: g),
                  ),
                );
              } else if (value == 'delete') {
                final ok = await confirmDialog(
                  context,
                  title: 'Eliminar grupo',
                  message: 'Se borrará el grupo y todo su historial.',
                  action: 'Eliminar',
                );
                if (ok && context.mounted) {
                  groupStore.delete(g.id);
                  Navigator.of(context).pop();
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem<String>(value: 'edit', child: Text('Editar grupo')),
              PopupMenuItem<String>(
                value: 'delete',
                child: Text('Eliminar grupo'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            Text(
              g.members.join(', '),
              style: t.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: g.members.length >= 3
                  ? () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SelectPlayersScreen(group: g),
                        ),
                      );
                    }
                  : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Jugar una partida'),
            ),
            const SizedBox(height: 28),
            const _SectionTitle('Clasificación general'),
            if (stats.isEmpty)
              Text(
                'Todavía no hay partidas. Las que juguéis desde este grupo '
                'aparecerán aquí.',
                style: t.textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              )
            else
              _StatsTable(stats: stats),
            const SizedBox(height: 28),
            const _SectionTitle('Historial'),
            if (games.isEmpty)
              Text(
                'Sin partidas guardadas.',
                style: t.textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              )
            else
              for (final r in games) _GameTile(groupId: g.id, record: r),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _StatsTable extends StatelessWidget {
  const _StatsTable({required this.stats});

  final List<PlayerStats> stats;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final head = t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant);

    Widget cell(String text, {TextStyle? style}) => SizedBox(
          width: 62,
          child: Text(text, textAlign: TextAlign.center, style: style),
        );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Expanded(child: Text('Jugador', style: head)),
              cell('Partidas', style: head),
              cell('Victorias', style: head),
              cell('Puntos', style: head),
            ],
          ),
        ),
        for (final s in stats)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.titleMedium,
                  ),
                ),
                cell('${s.games}', style: t.textTheme.bodyLarge),
                cell(
                  '${s.wins}',
                  style: t.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                cell(
                  '${s.points}',
                  style: t.textTheme.bodyLarge
                      ?.copyWith(color: ptsColor(context, s.points)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile({required this.groupId, required this.record});

  final String groupId;
  final GameRecord record;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final r = record;
    final names = r.winners.join(' y ');
    final title = r.winners.length == 1 ? 'Gana $names' : 'Empate: $names';
    final detail = '${fmtDate(r.date)} · '
        '${plural(r.players.length, 'jugador', 'jugadores')} · '
        '${r.deckSize} cartas';

    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text(title, style: t.textTheme.titleMedium),
      subtitle: Text(
        detail,
        style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      children: [
        for (final i in r.order)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Text(
                    '${r.rankOf(i)}º',
                    style: t.textTheme.bodyLarge
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                Expanded(
                  child: Text(
                    r.players[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.bodyLarge,
                  ),
                ),
                Text(
                  '${r.totals[i]} pts',
                  style: t.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: ptsColor(context, r.totals[i]),
                  ),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () async {
              final ok = await confirmDialog(
                context,
                title: 'Borrar partida',
                message: 'Se quitará del historial y de la clasificación.',
                action: 'Borrar',
              );
              if (ok && context.mounted) {
                groupStore.removeGame(groupId, r.id);
              }
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('Borrar partida'),
          ),
        ),
      ],
    );
  }
}

class SelectPlayersScreen extends StatefulWidget {
  const SelectPlayersScreen({super.key, required this.group});

  final PlayGroup group;

  @override
  State<SelectPlayersScreen> createState() => _SelectPlayersScreenState();
}

class _SelectPlayersScreenState extends State<SelectPlayersScreen> {
  late final Set<int> _selected = {
    for (var i = 0; i < widget.group.members.length && i < 10; i++) i,
  };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final members = widget.group.members;
    final count = _selected.length;
    final ok = count >= 3 && count <= 10;

    String info;
    if (count < 3) {
      info = 'Elige al menos 3 jugadores';
    } else if (count > 10) {
      info = 'Máximo 10 jugadores';
    } else {
      info = '$count jugadores';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('¿Quién juega?')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Se sientan en el orden de la lista.',
                style: t.textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: [
                    for (var i = 0; i < members.length; i++)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(members[i]),
                        value: _selected.contains(i),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(i);
                          } else {
                            _selected.remove(i);
                          }
                        }),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  info,
                  textAlign: TextAlign.center,
                  style: t.textTheme.bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              FilledButton(
                onPressed: ok
                    ? () {
                        final names = [
                          for (var i = 0; i < members.length; i++)
                            if (_selected.contains(i)) members[i],
                        ];
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SetupScreen(
                              fixedPlayers: names,
                              groupId: widget.group.id,
                            ),
                          ),
                        );
                      }
                    : null,
                child: const Text('Siguiente'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
