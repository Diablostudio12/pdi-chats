import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kUrl = 'https://jmmwvitwcrcpfxpeuuvm.supabase.co';
const kKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImptbXd2aXR3Y3JjcGZ4cGV1dXZtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTIxMTc2ODIsImV4cCI6MjEwNzY5MzY4Mn0.16bDDptai93FmPw3fmkiLAjJ64l3HMloRq-VEfy1WOw';

const vanilla = Color(0xFFFFFCD0);
const mist = Color(0xFF807E83);
const slate = Color(0xFF403D3E);
const ink = Color(0xFF262323);
const seenBlue = Color(0xFF4FA3FF);

SupabaseClient get sb => Supabase.instance.client;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: kUrl, anonKey: kKey);
  await Wall.load();
  runApp(const PdiApp());
}

// ---------- helpers ----------
String two(int x) => x.toString().padLeft(2, '0');

String fmtList(dynamic s) {
  final d = DateTime.parse(s.toString()).toLocal();
  final n = DateTime.now();
  if (d.year == n.year && d.month == n.month && d.day == n.day) return '${two(d.hour)}:${two(d.minute)}';
  final y = n.subtract(const Duration(days: 1));
  if (d.year == y.year && d.month == y.month && d.day == y.day) return 'Kal';
  return '${two(d.day)}/${two(d.month)}';
}

String fmtTime(dynamic s) {
  final d = DateTime.parse(s.toString()).toLocal();
  return '${two(d.hour)}:${two(d.minute)}';
}

Widget ticks(bool delivered, bool seen) => Icon(
    delivered || seen ? Icons.done_all : Icons.done,
    size: 16,
    color: seen ? seenBlue : mist);

Widget circ(IconData i) => Container(
    width: 42,
    height: 42,
    decoration: const BoxDecoration(color: slate, shape: BoxShape.circle),
    child: Icon(i, size: 20, color: vanilla));

Widget ibtn(IconData i, VoidCallback f) => Padding(
    padding: const EdgeInsets.only(left: 10),
    child: GestureDetector(onTap: f, child: circ(i)));

final List<LinearGradient> _grads = [
  const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [vanilla, Color(0xFFA9A78A)]),
  const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF9D9BA0), Color(0xFF5B585B)]),
  const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [vanilla, mist]),
  const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [mist, vanilla]),
];

class Av extends StatelessWidget {
  final String name;
  final double w;
  const Av(this.name, {this.w = 46, super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: w,
      height: w * 1.26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: _grads[name.hashCode.abs() % 4],
        borderRadius: BorderRadius.circular(w / 2),
        boxShadow: const [BoxShadow(color: Color(0x73000000), blurRadius: 8, offset: Offset(3, 4))],
      ),
      child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
          style: TextStyle(fontFamily: 'serif', fontWeight: FontWeight.w700, fontSize: w * 0.52, color: ink)),
    );
  }
}

// ---------- wallpaper ----------
class WP {
  final String type;
  final String v;
  final double dim;
  const WP(this.type, this.v, this.dim);
}

class Wall {
  static final n = ValueNotifier<WP>(const WP('p', '1', 0.35));
  static final List<BoxDecoration> presets = [
    const BoxDecoration(color: ink),
    const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [slate, ink])),
    const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF8F8D6E), slate, ink], stops: [0, 0.55, 1])),
    const BoxDecoration(gradient: RadialGradient(center: Alignment(-0.4, -0.6), radius: 1.2, colors: [mist, ink])),
    const BoxDecoration(gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFFD9D6B4), mist, ink], stops: [0, 0.4, 1])),
    const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomLeft, end: Alignment.topRight, colors: [mist, slate, ink])),
  ];

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    n.value = WP(p.getString('wp_t') ?? 'p', p.getString('wp_v') ?? '1', p.getDouble('wp_dim') ?? 0.35);
  }

  static Future<void> save(WP w) async {
    n.value = w;
    final p = await SharedPreferences.getInstance();
    await p.setString('wp_t', w.type);
    await p.setString('wp_v', w.v);
    await p.setDouble('wp_dim', w.dim);
  }

  static Future<void> pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
    if (x == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final f = await File(x.path).copy('${dir.path}/wp_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await save(WP('i', f.path, n.value.dim));
  }
}

class WallBg extends StatelessWidget {
  final Widget child;
  const WallBg({required this.child, super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WP>(
      valueListenable: Wall.n,
      builder: (_, w, __) {
        final img = w.type == 'i' && File(w.v).existsSync();
        final idx = (int.tryParse(w.v) ?? 1).clamp(0, Wall.presets.length - 1).toInt();
        return Stack(children: [
          Positioned.fill(
              child: img
                  ? Image.file(File(w.v), fit: BoxFit.cover)
                  : DecoratedBox(decoration: Wall.presets[idx])),
          Positioned.fill(child: ColoredBox(color: Color.fromRGBO(38, 35, 35, w.dim))),
          child,
        ]);
      },
    );
  }
}

void showWallpaper(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: slate,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
        child: ValueListenableBuilder<WP>(
          valueListenable: Wall.n,
          builder: (ctx, w, __) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Wallpaper', style: TextStyle(fontFamily: 'serif', fontSize: 28, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.6,
                physics: const NeverScrollableScrollPhysics(),
                children: List.generate(
                  Wall.presets.length,
                  (i) => GestureDetector(
                    onTap: () => Wall.save(WP('p', '$i', w.dim)),
                    child: Container(
                      decoration: Wall.presets[i].copyWith(
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: w.type == 'p' && w.v == '$i' ? vanilla : Colors.transparent, width: 2),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: Wall.pick,
                  style: FilledButton.styleFrom(backgroundColor: vanilla, foregroundColor: ink, padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('Gallery se chuno', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 10),
              const Text('Dhundla-pan', style: TextStyle(color: mist)),
              Slider(value: w.dim, min: 0, max: 0.8, activeColor: vanilla, onChanged: (v) => Wall.save(WP(w.type, w.v, v))),
            ],
          ),
        ),
      ),
    ),
  );
}

// ---------- realtime ----------
class Live {
  static final tick = ValueNotifier<int>(0);
  static RealtimeChannel? _c;
  static void start() {
    stop();
    _c = sb
        .channel('msgs')
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'messages',
            callback: (_) {
              tick.value++;
            })
        .subscribe();
  }

  static void stop() {
    if (_c != null) {
      sb.removeChannel(_c!);
      _c = null;
    }
  }
}

// ---------- app ----------
class PdiApp extends StatelessWidget {
  const PdiApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDI CHATS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: ink,
        colorScheme: const ColorScheme.dark(primary: vanilla, onPrimary: ink, surface: slate, onSurface: vanilla),
        textTheme: ThemeData.dark().textTheme.apply(bodyColor: vanilla, displayColor: vanilla),
      ),
      home: const Root(),
    );
  }
}

class Root extends StatelessWidget {
  const Root({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: sb.auth.onAuthStateChange,
      builder: (_, __) => sb.auth.currentSession != null ? const HomeScreen() : const AuthScreen(),
    );
  }
}

// ---------- login / register ----------
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthState();
}

class _AuthState extends State<AuthScreen> {
  bool login = true, busy = false;
  final user = TextEditingController(), name = TextEditingController(), pass = TextEditingController();

  InputDecoration deco(String h, {String? prefix}) => InputDecoration(
        hintText: h,
        prefixText: prefix,
        filled: true,
        fillColor: slate,
        hintStyle: const TextStyle(color: mist),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      );

  void say(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> submit() async {
    final u = user.text.trim().toLowerCase();
    final p = pass.text;
    if (u.isEmpty || p.isEmpty) return say('Username aur password likho');
    setState(() => busy = true);
    try {
      if (!login) {
        final r = await http.post(
          Uri.parse('$kUrl/functions/v1/register'),
          headers: {'Content-Type': 'application/json', 'apikey': kKey, 'Authorization': 'Bearer $kKey'},
          body: jsonEncode({'username': u, 'name': name.text.trim(), 'password': p}),
        );
        final d = jsonDecode(r.body);
        if (r.statusCode >= 400) throw (d['error'] ?? 'Error').toString();
      }
      await sb.auth.signInWithPassword(email: '$u@pdichats.app', password: p);
    } on AuthException {
      say('Username ya password galat hai');
    } catch (e) {
      say(e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('PDI CHATS', style: TextStyle(fontFamily: 'serif', fontSize: 42, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
              const SizedBox(height: 8),
              Text(login ? 'Login karo' : 'Naya account banao', style: const TextStyle(color: mist)),
              const SizedBox(height: 28),
              TextField(controller: user, autocorrect: false, enableSuggestions: false, decoration: deco('username', prefix: '@')),
              const SizedBox(height: 12),
              if (!login) ...[
                TextField(controller: name, decoration: deco('Tumhara naam')),
                const SizedBox(height: 12),
              ],
              TextField(controller: pass, obscureText: true, decoration: deco('Password')),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: busy ? null : submit,
                  style: FilledButton.styleFrom(backgroundColor: vanilla, foregroundColor: ink, padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: Text(busy ? 'Ruko...' : (login ? 'Login' : 'Account banao'), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => login = !login),
                child: Text(login ? 'Naya account banao' : 'Pehle se account hai? Login', style: const TextStyle(color: mist)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------- home ----------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeState();
}

class _HomeState extends State<HomeScreen> {
  List<Map<String, dynamic>> chats = [];
  bool unreadOnly = false;
  Timer? t;
  String get myName => (sb.auth.currentUser?.email ?? '').split('@').first;

  @override
  void initState() {
    super.initState();
    Live.start();
    load();
    Live.tick.addListener(load);
    t = Timer.periodic(const Duration(seconds: 20), (_) => load());
  }

  @override
  void dispose() {
    t?.cancel();
    Live.tick.removeListener(load);
    super.dispose();
  }

  Future<void> load() async {
    try {
      await sb.rpc('mark_delivered');
      final d = await sb.rpc('my_chats');
      if (!mounted) return;
      setState(() => chats = List<Map<String, dynamic>>.from((d as List).map((e) => Map<String, dynamic>.from(e))));
    } catch (_) {}
  }

  Future<void> openSearch() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()));
    load();
  }

  Widget chip(String label, bool on, VoidCallback f) => Padding(
        padding: const EdgeInsets.only(right: 10),
        child: GestureDetector(
          onTap: f,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
            decoration: BoxDecoration(color: on ? vanilla : slate, borderRadius: BorderRadius.circular(30)),
            child: Text(label, style: TextStyle(color: on ? ink : mist, fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final shown = unreadOnly ? chats.where((c) => ((c['unread'] ?? 0) as int) > 0).toList() : chats;
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: vanilla,
        foregroundColor: ink,
        shape: const CircleBorder(),
        onPressed: openSearch,
        child: const Icon(Icons.add, size: 28),
      ),
      body: WallBg(
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 6),
              child: Row(children: [
                const Expanded(child: Text('PDI CHATS', style: TextStyle(fontFamily: 'serif', fontSize: 36, fontWeight: FontWeight.w700, letterSpacing: 1.5))),
                ibtn(Icons.search, openSearch),
                ibtn(Icons.wallpaper, () => showWallpaper(context)),
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: PopupMenuButton<String>(
                    color: slate,
                    onSelected: (v) async {
                      if (v == 'out') {
                        Live.stop();
                        await sb.auth.signOut();
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem<String>(enabled: false, child: Text('@$myName')),
                      const PopupMenuItem<String>(value: 'out', child: Text('Logout')),
                    ],
                    child: circ(Icons.menu),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 8),
              child: Row(children: [
                chip('Sab', !unreadOnly, () => setState(() => unreadOnly = false)),
                chip('Unread', unreadOnly, () => setState(() => unreadOnly = true)),
              ]),
            ),
            Expanded(
              child: shown.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('Abhi koi chat nahi.\n+ dabake kisi ko username se dhundo.', textAlign: TextAlign.center, style: TextStyle(color: mist, fontSize: 15)),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 100),
                      itemCount: shown.length,
                      itemBuilder: (_, i) => tile(shown[i]),
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget tile(Map<String, dynamic> c) {
    final unread = (c['unread'] ?? 0) as int;
    final mine = c['mine'] == true;
    final col = unread > 0 ? vanilla : mist;
    final nm = (c['name'] ?? c['username']).toString();
    return InkWell(
      onTap: () async {
        await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => ChatScreen(peerId: c['peer_id'].toString(), username: c['username'].toString(), name: nm)));
        load();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        child: Row(children: [
          Av(nm),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(nm, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: col))),
                Text(fmtList(c['last_at']), style: TextStyle(fontSize: 12, color: col)),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                if (mine) ...[ticks(c['delivered'] == true, c['seen'] == true), const SizedBox(width: 5)],
                Expanded(child: Text((c['last_body'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, color: unread > 0 ? const Color(0xFFD9D6B4) : mist))),
                if (unread > 0)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: vanilla, borderRadius: BorderRadius.circular(20)),
                    child: Text('$unread', style: const TextStyle(color: ink, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ---------- search by username ----------
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchState();
}

class _SearchState extends State<SearchScreen> {
  List<Map<String, dynamic>> res = [];

  Future<void> search(String q) async {
    final s = q.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
    if (s.isEmpty) {
      setState(() => res = []);
      return;
    }
    try {
      final d = await sb.from('profiles').select('id,username,name').ilike('username', '$s%').neq('id', sb.auth.currentUser!.id).limit(20);
      if (!mounted) return;
      setState(() => res = List<Map<String, dynamic>>.from(d));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: WallBg(
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 22, 8),
              child: Row(children: [
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back)),
                Expanded(
                  child: TextField(
                    autofocus: true,
                    autocorrect: false,
                    onChanged: search,
                    decoration: InputDecoration(
                      hintText: 'Username likho',
                      prefixText: '@',
                      filled: true,
                      fillColor: slate,
                      hintStyle: const TextStyle(color: mist),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: res.length,
                itemBuilder: (_, i) {
                  final u = res[i];
                  final nm = (u['name'] ?? u['username']).toString();
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
                    leading: Av(nm),
                    title: Text(nm, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('@${u['username']}', style: const TextStyle(color: mist)),
                    onTap: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ChatScreen(peerId: u['id'].toString(), username: u['username'].toString(), name: nm))),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------- chat ----------
class ChatScreen extends StatefulWidget {
  final String peerId, username, name;
  const ChatScreen({required this.peerId, required this.username, required this.name, super.key});
  @override
  State<ChatScreen> createState() => _ChatState();
}

class _ChatState extends State<ChatScreen> {
  List<Map<String, dynamic>> msgs = [];
  final ctl = TextEditingController();
  Timer? poll, typingOff;
  DateTime lastSent = DateTime(2000);
  bool peerTyping = false;
  RealtimeChannel? tc;
  String get me => sb.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    load();
    Live.tick.addListener(load);
    poll = Timer.periodic(const Duration(seconds: 15), (_) => load());
    final ids = [me, widget.peerId]..sort();
    tc = sb.channel('typing_${ids[0]}_${ids[1]}').onBroadcast(
        event: 'typing',
        callback: (_) {
          if (!mounted) return;
          setState(() => peerTyping = true);
          typingOff?.cancel();
          typingOff = Timer(const Duration(seconds: 3), () {
            if (mounted) setState(() => peerTyping = false);
          });
        }).subscribe();
  }

  @override
  void dispose() {
    poll?.cancel();
    typingOff?.cancel();
    Live.tick.removeListener(load);
    if (tc != null) sb.removeChannel(tc!);
    ctl.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final d = await sb
          .from('messages')
          .select()
          .or('and(sender.eq.$me,receiver.eq.${widget.peerId}),and(sender.eq.${widget.peerId},receiver.eq.$me)')
          .order('id', ascending: false)
          .limit(300);
      if (!mounted) return;
      final list = List<Map<String, dynamic>>.from(d);
      setState(() => msgs = list);
      if (list.any((m) => m['sender'] == widget.peerId && m['seen'] == false)) {
        await sb.rpc('mark_seen', params: {'p_peer': widget.peerId});
      }
    } catch (_) {}
  }

  Future<void> send() async {
    final t = ctl.text.trim();
    if (t.isEmpty) return;
    ctl.clear();
    try {
      await sb.from('messages').insert({'sender': me, 'receiver': widget.peerId, 'body': t});
      await load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message nahi gaya, dobara try karo')));
    }
  }

  void onType(String _) {
    final n = DateTime.now();
    if (n.difference(lastSent).inSeconds < 2) return;
    lastSent = n;
    tc?.sendBroadcastMessage(event: 'typing', payload: {'from': me});
  }

  Widget bubble(Map<String, dynamic> m) {
    final mine = m['sender'] == me;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(14, 9, 12, 7),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: mine ? vanilla : slate,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(mine ? 20 : 6),
            bottomRight: Radius.circular(mine ? 6 : 20),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          Text(m['body'].toString(), style: TextStyle(color: mine ? ink : vanilla, fontSize: 15.5)),
          const SizedBox(height: 3),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(fmtTime(m['created_at']), style: TextStyle(fontSize: 11, color: mine ? slate : mist)),
            if (mine) ...[const SizedBox(width: 4), ticks(m['delivered'] == true, m['seen'] == true)],
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: WallBg(
        child: SafeArea(
          child: Column(children: [
            Container(
              color: const Color(0xE0262323),
              padding: const EdgeInsets.fromLTRB(6, 8, 16, 8),
              child: Row(children: [
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back)),
                Av(widget.name, w: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    Text(peerTyping ? 'typing...' : '@${widget.username}', style: TextStyle(fontSize: 12.5, color: peerTyping ? vanilla : mist)),
                  ]),
                ),
                ibtn(Icons.wallpaper, () => showWallpaper(context)),
              ]),
            ),
            Expanded(
              child: ListView.builder(
                reverse: true,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                itemCount: msgs.length,
                itemBuilder: (_, i) => bubble(msgs[i]),
              ),
            ),
            Container(
              color: const Color(0xE0262323),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: ctl,
                    onChanged: onType,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Message likho',
                      filled: true,
                      fillColor: slate,
                      hintStyle: const TextStyle(color: mist),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Material(
                  color: vanilla,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: send,
                    child: const Padding(padding: EdgeInsets.all(13), child: Icon(Icons.send_rounded, color: ink, size: 22)),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
