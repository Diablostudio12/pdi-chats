import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'main.dart';

// ---------- presence (online / last seen) ----------
Future<void> touchPresence() async {
  try {
    await sb.rpc('touch_presence');
  } catch (_) {}
}

String presenceText(dynamic iso) {
  if (iso == null) return '';
  final d = DateTime.parse(iso.toString()).toLocal();
  final n = DateTime.now();
  if (n.difference(d).inSeconds < 45) return 'online';
  final t = '${two(d.hour)}:${two(d.minute)}';
  if (d.year == n.year && d.month == n.month && d.day == n.day) return 'last seen aaj $t';
  final y = n.subtract(const Duration(days: 1));
  if (d.year == y.year && d.month == y.month && d.day == y.day) return 'last seen kal $t';
  return 'last seen ${two(d.day)}/${two(d.month)} $t';
}

// ---------- settings ----------
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsScreen> {
  bool hideSeen = false, busy = false;
  String get me => sb.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await sb.from('presence').select('hide').eq('user_id', me).maybeSingle();
      if (mounted) setState(() => hideSeen = r != null && r['hide'] == true);
    } catch (_) {}
  }

  Future<void> setHide(bool v) async {
    setState(() => hideSeen = v);
    try {
      await sb.from('presence').upsert({'user_id': me, 'hide': v});
    } catch (_) {
      if (mounted) {
        setState(() => hideSeen = !v);
        toast(context, 'Save nahi hua');
      }
    }
  }

  Future<void> backup() async {
    setState(() => busy = true);
    try {
      final all = <Map<String, dynamic>>[];
      var from = 0;
      while (true) {
        final d = await sb.from('messages').select().order('id').range(from, from + 999);
        final l = List<Map<String, dynamic>>.from(d);
        all.addAll(l);
        if (l.length < 1000) break;
        from += 1000;
      }
      final pids = <String>{};
      final cids = <String>{};
      for (final m in all) {
        pids.add(m['sender'].toString());
        if (m['receiver'] != null) pids.add(m['receiver'].toString());
        if (m['conv_id'] != null) cids.add(m['conv_id'].toString());
      }
      final pn = <String, String>{};
      if (pids.isNotEmpty) {
        final ps = await sb.from('profiles').select('id,name,username').inFilter('id', pids.toList());
        for (final p in List<Map<String, dynamic>>.from(ps)) {
          pn[p['id'].toString()] = '${p['name']} (@${p['username']})';
        }
      }
      final cn = <String, String>{};
      if (cids.isNotEmpty) {
        final cs = await sb.from('conversations').select('id,name').inFilter('id', cids.toList());
        for (final c in List<Map<String, dynamic>>.from(cs)) {
          cn[c['id'].toString()] = c['name'].toString();
        }
      }
      final groups = <String, List<Map<String, dynamic>>>{};
      for (final m in all) {
        final String key;
        if (m['conv_id'] != null) {
          key = 'Group: ${cn[m['conv_id'].toString()] ?? 'Group'}';
        } else {
          final peer = (m['sender'] == me ? m['receiver'] : m['sender']).toString();
          key = 'Chat: ${pn[peer] ?? 'User'}';
        }
        groups.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(m);
      }
      final b = StringBuffer('PDI CHATS backup\n');
      groups.forEach((k, list) {
        b.writeln('\n===== $k =====');
        for (final m in list) {
          final d = DateTime.parse(m['created_at'].toString()).toLocal();
          final who = m['sender'] == me ? 'Tum' : (pn[m['sender'].toString()] ?? 'User');
          final url = m['media_url'] == null ? '' : ' ${m['media_url']}';
          final txt = m['deleted'] == true ? '(delete kiya gaya)' : '${previewMsg(m)}$url';
          b.writeln('[${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}] $who: $txt');
        }
      });
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/pdi_chats_backup.txt');
      await f.writeAsString(b.toString());
      await Share.shareXFiles([XFile(f.path)], text: 'PDI CHATS backup');
    } catch (_) {
      if (mounted) toast(context, 'Backup nahi bana, dobara try karo');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: ink, title: const Text('Settings')),
      body: ListView(children: [
        if (busy) const LinearProgressIndicator(minHeight: 2, color: vanilla, backgroundColor: slate),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          value: hideSeen,
          onChanged: setHide,
          activeColor: vanilla,
          title: const Text('Last seen / online chhupao'),
          subtitle: const Text('Dusre tumhara last seen nahi dekh paayenge', style: TextStyle(color: mist, fontSize: 12.5)),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: const Icon(Icons.block, color: mist),
          title: const Text('Blocked users'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BlockedScreen())),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: const Icon(Icons.backup, color: mist),
          title: const Text('Chat backup'),
          subtitle: const Text('Saari chats ek text file me, share ya save karo', style: TextStyle(color: mist, fontSize: 12.5)),
          onTap: busy ? null : backup,
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: const Icon(Icons.wallpaper, color: mist),
          title: const Text('Wallpaper'),
          onTap: () => showWallpaper(context),
        ),
      ]),
    );
  }
}

// ---------- blocked users ----------
class BlockedScreen extends StatefulWidget {
  const BlockedScreen({super.key});
  @override
  State<BlockedScreen> createState() => _BlockedState();
}

class _BlockedState extends State<BlockedScreen> {
  List<Map<String, dynamic>> users = [];
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final b = await sb.from('blocks').select('blocked');
      final ids = List<Map<String, dynamic>>.from(b).map((r) => r['blocked'].toString()).toList();
      var list = <Map<String, dynamic>>[];
      if (ids.isNotEmpty) {
        final ps = await sb.from('profiles').select('id,name,username,avatar_url').inFilter('id', ids);
        list = List<Map<String, dynamic>>.from(ps);
      }
      if (mounted) {
        setState(() {
          users = list;
          loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => loaded = true);
    }
  }

  Future<void> unblock(String id) async {
    try {
      await sb.from('blocks').delete().eq('blocked', id);
      await load();
    } catch (_) {
      if (mounted) toast(context, 'Unblock nahi hua');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: ink, title: const Text('Blocked users')),
      body: !loaded
          ? const Center(child: CircularProgressIndicator(color: vanilla))
          : users.isEmpty
              ? const Center(child: Text('Kisi ko block nahi kiya', style: TextStyle(color: mist)))
              : ListView(
                  children: users
                      .map((u) => ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
                            leading: Av((u['name'] ?? u['username']).toString(), url: u['avatar_url']?.toString(), w: 38),
                            title: Text((u['name'] ?? u['username']).toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text('@${u['username']}', style: const TextStyle(color: mist)),
                            trailing: TextButton(onPressed: () => unblock(u['id'].toString()), child: const Text('Unblock')),
                          ))
                      .toList(),
                ),
    );
  }
}

// ---------- starred messages ----------
class StarredScreen extends StatefulWidget {
  const StarredScreen({super.key});
  @override
  State<StarredScreen> createState() => _StarredState();
}

class _StarredState extends State<StarredScreen> {
  List<Map<String, dynamic>> items = [];
  Map<String, String> names = {};
  bool loaded = false;
  String get me => sb.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final d = await sb
          .from('starred')
          .select('message_id, messages(id,body,kind,sender,created_at,media_name,deleted,view_once)')
          .order('created_at', ascending: false);
      final list = <Map<String, dynamic>>[];
      final ids = <String>{};
      for (final r in List<Map<String, dynamic>>.from(d)) {
        if (r['messages'] is Map) {
          final m = Map<String, dynamic>.from(r['messages'] as Map);
          if (m['deleted'] == true) continue;
          list.add(m);
          ids.add(m['sender'].toString());
        }
      }
      final nm = <String, String>{};
      if (ids.isNotEmpty) {
        final ps = await sb.from('profiles').select('id,name').inFilter('id', ids.toList());
        for (final p in List<Map<String, dynamic>>.from(ps)) {
          nm[p['id'].toString()] = (p['name'] ?? '').toString();
        }
      }
      if (!mounted) return;
      setState(() {
        items = list;
        names = nm;
        loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => loaded = true);
    }
  }

  Future<void> unstar(int id) async {
    try {
      await sb.from('starred').delete().eq('message_id', id);
      await load();
    } catch (_) {
      if (mounted) toast(context, 'Unstar nahi hua');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: ink, title: const Text('Starred messages')),
      body: !loaded
          ? const Center(child: CircularProgressIndicator(color: vanilla))
          : items.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Koi starred message nahi. Message ko dabake rakho aur Star chuno.', textAlign: TextAlign.center, style: TextStyle(color: mist)),
                  ),
                )
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final m = items[i];
                    final who = m['sender'] == me ? 'Tum' : (names[m['sender'].toString()] ?? 'User');
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
                      title: Text('$who  |  ${fmtList(m['created_at'])}', style: const TextStyle(color: mist, fontSize: 13, fontWeight: FontWeight.w700)),
                      subtitle: Text(previewMsg(m), maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15.5)),
                      trailing: IconButton(icon: const Icon(Icons.star, color: vanilla), onPressed: () => unstar(m['id'] as int)),
                    );
                  },
                ),
    );
  }
}

// ---------- status / stories ----------
const kStatusBgs = [Color(0xFF403D3E), Color(0xFF8F8D6E), Color(0xFF5B585B), Color(0xFFA9A78A), Color(0xFF262323)];
Color statusFg(int i) => (i == 1 || i == 3) ? ink : vanilla;

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});
  @override
  State<StatusScreen> createState() => _StatusState();
}

class _StatusState extends State<StatusScreen> {
  List<Map<String, dynamic>> mine = [];
  Map<String, List<Map<String, dynamic>>> others = {};
  Map<String, Map<String, dynamic>> info = {};
  bool busy = false;
  String get me => sb.auth.currentUser!.id;
  String get myName => (sb.auth.currentUser?.email ?? '').split('@').first;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final d = await sb.from('statuses').select().order('created_at');
      final m = <Map<String, dynamic>>[];
      final o = <String, List<Map<String, dynamic>>>{};
      for (final s in List<Map<String, dynamic>>.from(d)) {
        if (s['user_id'] == me) {
          m.add(s);
        } else {
          o.putIfAbsent(s['user_id'].toString(), () => <Map<String, dynamic>>[]).add(s);
        }
      }
      final inf = <String, Map<String, dynamic>>{};
      if (o.isNotEmpty) {
        final ps = await sb.from('profiles').select('id,name,username,avatar_url').inFilter('id', o.keys.toList());
        for (final p in List<Map<String, dynamic>>.from(ps)) {
          inf[p['id'].toString()] = p;
        }
      }
      if (!mounted) return;
      setState(() {
        mine = m;
        others = o;
        info = inf;
      });
    } catch (_) {}
  }

  Future<void> addText() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const TextStatusScreen()));
    load();
  }

  Future<void> addPhoto() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 80);
    if (x == null) return;
    setState(() => busy = true);
    try {
      final url = await uploadFile(File(x.path), x.name);
      await sb.from('statuses').insert({'kind': 'image', 'media_url': url});
      await load();
    } catch (_) {
      if (mounted) toast(context, 'Status upload nahi hua');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void addMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: slate,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          ListTile(
            leading: const Icon(Icons.text_fields),
            title: const Text('Text status'),
            onTap: () {
              Navigator.pop(ctx);
              addText();
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo),
            title: const Text('Photo status'),
            onTap: () {
              Navigator.pop(ctx);
              addPhoto();
            },
          ),
          const SizedBox(height: 10),
        ]),
      ),
    );
  }

  Future<void> open(List<Map<String, dynamic>> items, String name, bool isMine) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => StatusViewer(items, name, isMine)));
    load();
  }

  @override
  Widget build(BuildContext context) {
    final keys = others.keys.toList()
      ..sort((a, b) => DateTime.parse(others[b]!.last['created_at'].toString()).compareTo(DateTime.parse(others[a]!.last['created_at'].toString())));
    return Scaffold(
      appBar: AppBar(backgroundColor: ink, title: const Text('Status')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: vanilla,
        foregroundColor: ink,
        onPressed: busy ? null : addMenu,
        child: const Icon(Icons.add),
      ),
      body: ListView(children: [
        if (busy) const LinearProgressIndicator(minHeight: 2, color: vanilla, backgroundColor: slate),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
          leading: Av(myName, w: 46),
          title: const Text('Mera status', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            mine.isEmpty ? 'Status daalo, 24 ghante me gayab ho jayega' : '${mine.length} status  |  ${fmtList(mine.last['created_at'])}',
            style: const TextStyle(color: mist),
          ),
          onTap: mine.isEmpty ? addMenu : () => open(mine, 'Tum', true),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 16, 6),
          child: Text('Recent', style: TextStyle(color: mist, fontWeight: FontWeight.w700)),
        ),
        if (keys.isEmpty)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Text('Abhi kisi ne status nahi daala', style: TextStyle(color: mist)),
          ),
        ...keys.map((k) {
          final p = info[k];
          final nm = (p?['name'] ?? p?['username'] ?? 'User').toString();
          final list = others[k]!;
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
            leading: Av(nm, url: p?['avatar_url']?.toString(), w: 46),
            title: Text(nm, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${list.length} status  |  ${fmtList(list.last['created_at'])}', style: const TextStyle(color: mist)),
            onTap: () => open(list, nm, false),
          );
        }),
        const SizedBox(height: 90),
      ]),
    );
  }
}

class TextStatusScreen extends StatefulWidget {
  const TextStatusScreen({super.key});
  @override
  State<TextStatusScreen> createState() => _TextStatusState();
}

class _TextStatusState extends State<TextStatusScreen> {
  final ctl = TextEditingController();
  int bg = 0;
  bool busy = false;

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  Future<void> post() async {
    final t = ctl.text.trim();
    if (t.isEmpty) return;
    setState(() => busy = true);
    try {
      await sb.from('statuses').insert({'kind': 'text', 'body': t, 'bg': bg});
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => busy = false);
        toast(context, 'Status nahi gaya');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kStatusBgs[bg],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: statusFg(bg),
        actions: [IconButton(onPressed: () => setState(() => bg = (bg + 1) % kStatusBgs.length), icon: const Icon(Icons.palette))],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: TextField(
            controller: ctl,
            autofocus: true,
            textAlign: TextAlign.center,
            maxLines: null,
            maxLength: 300,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: statusFg(bg)),
            decoration: const InputDecoration(border: InputBorder.none, hintText: 'Kuch likho...', hintStyle: TextStyle(color: mist), counterText: ''),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: vanilla,
        foregroundColor: ink,
        onPressed: busy ? null : post,
        child: const Icon(Icons.send),
      ),
    );
  }
}

class StatusViewer extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final String name;
  final bool mine;
  const StatusViewer(this.items, this.name, this.mine, {super.key});
  @override
  State<StatusViewer> createState() => _ViewerState();
}

class _ViewerState extends State<StatusViewer> {
  int i = 0;
  Timer? t;

  @override
  void initState() {
    super.initState();
    arm();
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  void arm() {
    t?.cancel();
    t = Timer(const Duration(seconds: 5), next);
  }

  void next() {
    if (!mounted) return;
    if (i < widget.items.length - 1) {
      setState(() => i++);
      arm();
    } else {
      Navigator.pop(context);
    }
  }

  void prev() {
    if (i > 0) {
      setState(() => i--);
      arm();
    }
  }

  Future<void> del() async {
    final s = widget.items[i];
    try {
      await sb.from('statuses').delete().eq('id', s['id']);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) toast(context, 'Delete nahi hua');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.items[i];
    final isImg = s['kind'] == 'image';
    final bg = ((s['bg'] ?? 0) as int).clamp(0, kStatusBgs.length - 1).toInt();
    final w = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => d.globalPosition.dx < w / 3 ? prev() : next(),
        child: Stack(children: [
          Positioned.fill(
            child: isImg
                ? Image.network(
                    (s['media_url'] ?? '').toString(),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, color: mist)),
                  )
                : Container(
                    color: kStatusBgs[bg],
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(28),
                    child: Text((s['body'] ?? '').toString(), textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: statusFg(bg))),
                  ),
          ),
          SafeArea(
            child: Container(
              color: const Color(0x66000000),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(
                  children: List.generate(
                    widget.items.length,
                    (k) => Expanded(
                      child: Container(
                        height: 3,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(color: k <= i ? vanilla : mist, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back)),
                  Expanded(child: Text('${widget.name}  |  ${fmtList(s['created_at'])}', style: const TextStyle(fontWeight: FontWeight.w700))),
                  if (widget.mine) IconButton(onPressed: del, icon: const Icon(Icons.delete_outline, color: Color(0xFFFF7A7A))),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
