import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

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

String fmtDur(Duration d) => '${d.inMinutes}:${two(d.inSeconds % 60)}';

String fmtSize(int b) {
  if (b < 1024) return '$b B';
  if (b < 1048576) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '${(b / 1048576).toStringAsFixed(1)} MB';
}

String mimeOf(String ext) {
  const m = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'mkv': 'video/x-matroska',
    'm4a': 'audio/mp4',
    'mp3': 'audio/mpeg',
    'wav': 'audio/wav',
    'pdf': 'application/pdf',
  };
  return m[ext] ?? 'application/octet-stream';
}

void toast(BuildContext c, String m) {
  ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));
}

String previewMsg(Map<String, dynamic> m) {
  if (m['deleted'] == true) return 'Message delete kiya gaya';
  switch ((m['kind'] ?? 'text').toString()) {
    case 'image':
      return '📷 Photo';
    case 'video':
      return '🎥 Video';
    case 'voice':
      return '🎤 Voice message';
    case 'file':
      return '📄 ${m['media_name'] ?? 'File'}';
    default:
      return (m['body'] ?? '').toString();
  }
}

String previewOf(Map<String, dynamic> c) =>
    previewMsg({'deleted': c['last_deleted'], 'kind': c['last_kind'], 'body': c['last_body']});

Future<String> uploadFile(File f, String name) async {
  final uid = sb.auth.currentUser!.id;
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'bin';
  final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
  await sb.storage.from('media').upload(path, f, fileOptions: FileOptions(contentType: mimeOf(ext)));
  return sb.storage.from('media').getPublicUrl(path);
}

Future<void> insertMessage(String to,
    {String body = '', String kind = 'text', String? url, String? mname, int? msize, int? dur, int? replyTo, bool fwd = false}) async {
  await sb.from('messages').insert({
    'sender': sb.auth.currentUser!.id,
    'receiver': to,
    'body': body,
    'kind': kind,
    'media_url': url,
    'media_name': mname,
    'media_size': msize,
    'duration': dur,
    'reply_to': replyTo,
    'forwarded': fwd,
  });
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
  final String? url;
  final double w;
  const Av(this.name, {this.url, this.w = 46, super.key});

  Widget initial() => Text(name.isEmpty ? '?' : name[0].toUpperCase(),
      style: TextStyle(fontFamily: 'serif', fontWeight: FontWeight.w700, fontSize: w * 0.52, color: ink));

  @override
  Widget build(BuildContext context) {
    final has = url != null && url!.isNotEmpty;
    final h = w * 1.26;
    return Container(
      width: w,
      height: h,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: has ? null : _grads[name.hashCode.abs() % 4],
        borderRadius: BorderRadius.circular(w / 2),
        boxShadow: const [BoxShadow(color: Color(0x73000000), blurRadius: 8, offset: Offset(3, 4))],
      ),
      child: has
          ? Image.network(url!, width: w, height: h, fit: BoxFit.cover, errorBuilder: (_, __, ___) => initial())
          : initial(),
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
  static RealtimeChannel? _c, _r;
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
    _r = sb
        .channel('reacts')
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'message_reactions',
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
    if (_r != null) {
      sb.removeChannel(_r!);
      _r = null;
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
    if (mounted) toast(context, m);
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
                      if (v == 'profile') {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
                        load();
                      } else if (v == 'out') {
                        Live.stop();
                        await sb.auth.signOut();
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem<String>(enabled: false, child: Text('@$myName')),
                      const PopupMenuItem<String>(value: 'profile', child: Text('Profile')),
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
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text('Abhi koi chat nahi.', style: TextStyle(color: mist, fontSize: 15)),
                          SizedBox(height: 4),
                          Text('+ dabake kisi ko username se dhundo.', textAlign: TextAlign.center, style: TextStyle(color: mist, fontSize: 15)),
                        ]),
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
    final av = c['avatar_url']?.toString();
    return InkWell(
      onTap: () async {
        await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => ChatScreen(peerId: c['peer_id'].toString(), username: c['username'].toString(), name: nm, avatar: av)));
        load();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        child: Row(children: [
          Av(nm, url: av),
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
                Expanded(child: Text(previewOf(c), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, color: unread > 0 ? const Color(0xFFD9D6B4) : mist))),
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

// ---------- profile ----------
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfState();
}

class _ProfState extends State<ProfileScreen> {
  Map<String, dynamic>? p;
  bool busy = false;
  String get me => sb.auth.currentUser!.id;
  String get uname => (sb.auth.currentUser?.email ?? '').split('@').first;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final d = await sb.from('profiles').select().eq('id', me).single();
      if (mounted) setState(() => p = Map<String, dynamic>.from(d));
    } catch (_) {}
  }

  Future<void> changePhoto() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
    if (x == null) return;
    setState(() => busy = true);
    try {
      final url = await uploadFile(File(x.path), x.name);
      await sb.from('profiles').update({'avatar_url': url}).eq('id', me);
      await load();
    } catch (_) {
      if (mounted) toast(context, 'Photo upload nahi hui');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit(String field, String title, int max) async {
    final c = TextEditingController(text: p?[field]?.toString() ?? '');
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: slate,
        title: Text(title),
        content: TextField(controller: c, maxLength: max, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: mist))),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (v == null || v.isEmpty) return;
    try {
      await sb.from('profiles').update({field: v}).eq('id', me);
      await load();
    } catch (_) {
      if (mounted) toast(context, 'Save nahi hua');
    }
  }

  Widget row(IconData i, String label, String value, VoidCallback? f) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 26, vertical: 4),
        leading: Icon(i, color: mist),
        title: Text(label, style: const TextStyle(color: mist, fontSize: 13)),
        subtitle: Text(value, style: const TextStyle(fontSize: 17)),
        trailing: f == null ? null : const Icon(Icons.edit, size: 18, color: mist),
        onTap: f,
      );

  @override
  Widget build(BuildContext context) {
    final nm = (p?['name'] ?? uname).toString();
    return Scaffold(
      body: SafeArea(
        child: ListView(children: [
          Align(alignment: Alignment.centerLeft, child: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back))),
          const SizedBox(height: 6),
          Center(
            child: GestureDetector(
              onTap: busy ? null : changePhoto,
              child: Stack(alignment: Alignment.bottomRight, children: [
                Av(nm, url: p?['avatar_url']?.toString(), w: 120),
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: const BoxDecoration(color: vanilla, shape: BoxShape.circle),
                  child: busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: ink))
                      : const Icon(Icons.photo_camera, size: 18, color: ink),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 24),
          row(Icons.person, 'Naam', nm, () => edit('name', 'Naam badlo', 40)),
          row(Icons.info_outline, 'About', (p?['about'] ?? '').toString(), () => edit('about', 'About badlo', 100)),
          row(Icons.alternate_email, 'Username', '@$uname', null),
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
      final d = await sb.from('profiles').select('id,username,name,avatar_url').ilike('username', '$s%').neq('id', sb.auth.currentUser!.id).limit(20);
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
                  final av = u['avatar_url']?.toString();
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
                    leading: Av(nm, url: av),
                    title: Text(nm, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('@${u['username']}', style: const TextStyle(color: mist)),
                    onTap: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ChatScreen(peerId: u['id'].toString(), username: u['username'].toString(), name: nm, avatar: av))),
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

// ---------- forward ----------
class ForwardScreen extends StatefulWidget {
  final Map<String, dynamic> msg;
  const ForwardScreen(this.msg, {super.key});
  @override
  State<ForwardScreen> createState() => _FwdState();
}

class _FwdState extends State<ForwardScreen> {
  List<Map<String, dynamic>> chats = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final d = await sb.rpc('my_chats');
      if (!mounted) return;
      setState(() => chats = List<Map<String, dynamic>>.from((d as List).map((e) => Map<String, dynamic>.from(e))));
    } catch (_) {}
  }

  Future<void> send(Map<String, dynamic> c) async {
    final m = widget.msg;
    try {
      await insertMessage(c['peer_id'].toString(),
          body: (m['body'] ?? '').toString(),
          kind: (m['kind'] ?? 'text').toString(),
          url: m['media_url']?.toString(),
          mname: m['media_name']?.toString(),
          msize: m['media_size'] as int?,
          dur: m['duration'] as int?,
          fwd: true);
      if (!mounted) return;
      Navigator.pop(context);
      toast(context, 'Forward ho gaya');
    } catch (_) {
      if (mounted) toast(context, 'Forward nahi hua');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: ink, title: const Text('Forward karo')),
      body: chats.isEmpty
          ? const Center(child: Text('Pehle kisi se chat shuru karo', style: TextStyle(color: mist)))
          : ListView.builder(
              itemCount: chats.length,
              itemBuilder: (_, i) {
                final c = chats[i];
                final nm = (c['name'] ?? c['username']).toString();
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
                  leading: Av(nm, url: c['avatar_url']?.toString()),
                  title: Text(nm, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('@${c['username']}', style: const TextStyle(color: mist)),
                  onTap: () => send(c),
                );
              },
            ),
    );
  }
}

// ---------- media viewers ----------
class ImageView extends StatelessWidget {
  final String url;
  const ImageView(this.url, {super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black),
      body: Center(child: InteractiveViewer(child: Image.network(url))),
    );
  }
}

class VideoScreen extends StatefulWidget {
  final String url;
  const VideoScreen(this.url, {super.key});
  @override
  State<VideoScreen> createState() => _VideoState();
}

class _VideoState extends State<VideoScreen> {
  late VideoPlayerController c;
  bool ready = false;

  @override
  void initState() {
    super.initState();
    c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    c.addListener(() {
      if (mounted) setState(() {});
    });
    c.initialize().then((_) {
      if (mounted) {
        setState(() => ready = true);
        c.play();
      }
    });
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  void toggle() => c.value.isPlaying ? c.pause() : c.play();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black),
      body: Center(
        child: ready
            ? GestureDetector(
                onTap: toggle,
                child: AspectRatio(
                  aspectRatio: c.value.aspectRatio,
                  child: Stack(alignment: Alignment.bottomCenter, children: [
                    VideoPlayer(c),
                    VideoProgressIndicator(c, allowScrubbing: true, colors: const VideoProgressColors(playedColor: vanilla)),
                  ]),
                ),
              )
            : const CircularProgressIndicator(color: vanilla),
      ),
      floatingActionButton: ready
          ? FloatingActionButton(
              backgroundColor: vanilla,
              foregroundColor: ink,
              onPressed: toggle,
              child: Icon(c.value.isPlaying ? Icons.pause : Icons.play_arrow),
            )
          : null,
    );
  }
}

class VoicePlayer extends StatefulWidget {
  final String url;
  final int dur;
  final bool mine;
  const VoicePlayer({required this.url, required this.dur, required this.mine, super.key});
  @override
  State<VoicePlayer> createState() => _VPState();
}

class _VPState extends State<VoicePlayer> {
  final p = AudioPlayer();
  bool playing = false;
  Duration pos = Duration.zero;
  Duration total = Duration.zero;

  @override
  void initState() {
    super.initState();
    total = Duration(seconds: widget.dur);
    p.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => playing = s == PlayerState.playing);
    });
    p.onPositionChanged.listen((d) {
      if (mounted) setState(() => pos = d);
    });
    p.onDurationChanged.listen((d) {
      if (mounted && d.inMilliseconds > 0) setState(() => total = d);
    });
    p.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          playing = false;
          pos = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    p.dispose();
    super.dispose();
  }

  Future<void> toggle() async {
    if (playing) {
      await p.pause();
    } else if (pos > Duration.zero && pos < total) {
      await p.resume();
    } else {
      await p.play(UrlSource(widget.url));
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.mine ? ink : vanilla;
    final tm = math.max(total.inMilliseconds, 1);
    final val = math.min(pos.inMilliseconds, tm) / tm;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      GestureDetector(onTap: toggle, child: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_fill, size: 38, color: fg)),
      SizedBox(
        width: 140,
        child: Slider(
          value: val.toDouble(),
          activeColor: fg,
          inactiveColor: mist,
          onChanged: (v) => p.seek(Duration(milliseconds: (v * tm).toInt())),
        ),
      ),
      Text(fmtDur(playing || pos > Duration.zero ? pos : total), style: TextStyle(fontSize: 12, color: fg)),
    ]);
  }
}

// ---------- chat ----------
class ChatScreen extends StatefulWidget {
  final String peerId, username, name;
  final String? avatar;
  const ChatScreen({required this.peerId, required this.username, required this.name, this.avatar, super.key});
  @override
  State<ChatScreen> createState() => _ChatState();
}

class _ChatState extends State<ChatScreen> {
  List<Map<String, dynamic>> msgs = [];
  Map<int, Map<String, int>> reacts = {};
  Map<int, String> myReact = {};
  final ctl = TextEditingController();
  final rec = AudioRecorder();
  Timer? poll, typingOff, recT;
  DateTime lastSent = DateTime(2000);
  bool peerTyping = false, uploading = false, recording = false;
  int recSecs = 0;
  Map<String, dynamic>? replyTo;
  RealtimeChannel? tc;
  String get me => sb.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    load();
    Live.tick.addListener(load);
    ctl.addListener(() {
      if (mounted) setState(() {});
    });
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
    recT?.cancel();
    Live.tick.removeListener(load);
    if (tc != null) sb.removeChannel(tc!);
    rec.dispose();
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
      final ids = list.map((m) => m['id'] as int).toList();
      if (ids.isNotEmpty) {
        final rs = await sb.from('message_reactions').select().inFilter('message_id', ids);
        final rm = <int, Map<String, int>>{};
        final mine = <int, String>{};
        for (final r in List<Map<String, dynamic>>.from(rs)) {
          final id = r['message_id'] as int;
          final e = r['emoji'].toString();
          rm.putIfAbsent(id, () => <String, int>{});
          rm[id]![e] = (rm[id]![e] ?? 0) + 1;
          if (r['user_id'] == me) mine[id] = e;
        }
        if (mounted) {
          setState(() {
            reacts = rm;
            myReact = mine;
          });
        }
      }
      if (list.any((m) => m['sender'] == widget.peerId && m['seen'] == false)) {
        await sb.rpc('mark_seen', params: {'p_peer': widget.peerId});
      }
    } catch (_) {}
  }

  Future<void> sendText() async {
    final t = ctl.text.trim();
    if (t.isEmpty) return;
    final rid = replyTo?['id'] as int?;
    ctl.clear();
    setState(() => replyTo = null);
    try {
      await insertMessage(widget.peerId, body: t, replyTo: rid);
      await load();
    } catch (_) {
      if (mounted) toast(context, 'Message nahi gaya, dobara try karo');
    }
  }

  Future<void> sendMedia(File f, String name, String kind, {int? dur}) async {
    final size = await f.length();
    if (size > 50 * 1024 * 1024) {
      if (mounted) toast(context, '50 MB se badi file nahi bhej sakte');
      return;
    }
    final rid = replyTo?['id'] as int?;
    setState(() => uploading = true);
    try {
      final url = await uploadFile(f, name);
      await insertMessage(widget.peerId, kind: kind, url: url, mname: name, msize: size, dur: dur, replyTo: rid);
      if (mounted) setState(() => replyTo = null);
      await load();
    } catch (_) {
      if (mounted) toast(context, 'Upload nahi hua, dobara try karo');
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> pickImg(ImageSource s) async {
    final x = await ImagePicker().pickImage(source: s, maxWidth: 1600, imageQuality: 80);
    if (x != null) await sendMedia(File(x.path), x.name, 'image');
  }

  Future<void> pickVid() async {
    final x = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (x != null) await sendMedia(File(x.path), x.name, 'video');
  }

  Future<void> pickDoc() async {
    final r = await FilePicker.platform.pickFiles();
    final f = r?.files.single;
    if (f != null && f.path != null) await sendMedia(File(f.path!), f.name, 'file');
  }

  Widget opt(BuildContext ctx, IconData i, String label, Future<void> Function() f) => GestureDetector(
        onTap: () {
          Navigator.pop(ctx);
          f();
        },
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(color: vanilla, shape: BoxShape.circle),
            child: Icon(i, color: ink),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12.5, color: mist)),
        ]),
      );

  void attach() {
    showModalBottomSheet(
      context: context,
      backgroundColor: slate,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            opt(ctx, Icons.photo, 'Photo', () => pickImg(ImageSource.gallery)),
            opt(ctx, Icons.photo_camera, 'Camera', () => pickImg(ImageSource.camera)),
            opt(ctx, Icons.videocam, 'Video', pickVid),
            opt(ctx, Icons.insert_drive_file, 'File', pickDoc),
          ]),
        ),
      ),
    );
  }

  Future<void> startRec() async {
    try {
      if (!await rec.hasPermission()) {
        if (mounted) toast(context, 'Mic ki permission do');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/v${DateTime.now().millisecondsSinceEpoch}.m4a';
      await rec.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      setState(() {
        recording = true;
        recSecs = 0;
      });
      recT = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => recSecs++);
      });
    } catch (_) {
      if (mounted) toast(context, 'Recording shuru nahi hui');
    }
  }

  Future<void> stopRec({required bool send}) async {
    recT?.cancel();
    final secs = recSecs;
    String? path;
    try {
      path = await rec.stop();
    } catch (_) {}
    if (mounted) setState(() => recording = false);
    if (!send || path == null || secs < 1) return;
    await sendMedia(File(path), 'voice.m4a', 'voice', dur: secs);
  }

  void onType(String _) {
    final n = DateTime.now();
    if (n.difference(lastSent).inSeconds < 2) return;
    lastSent = n;
    tc?.sendBroadcastMessage(event: 'typing', payload: {'from': me});
  }

  Future<void> react(Map<String, dynamic> m, String e) async {
    final id = m['id'] as int;
    try {
      if (myReact[id] == e) {
        await sb.from('message_reactions').delete().eq('message_id', id).eq('user_id', me);
      } else {
        await sb.from('message_reactions').upsert({'message_id': id, 'user_id': me, 'emoji': e}, onConflict: 'message_id,user_id');
      }
      await load();
    } catch (_) {
      if (mounted) toast(context, 'Reaction nahi lagi');
    }
  }

  Future<void> deleteMsg(Map<String, dynamic> m) async {
    try {
      await sb.rpc('delete_message', params: {'p_id': m['id']});
      await load();
    } catch (_) {
      if (mounted) toast(context, 'Delete nahi hua');
    }
  }

  void actions(Map<String, dynamic> m) {
    final mine = m['sender'] == me;
    final kind = (m['kind'] ?? 'text').toString();
    showModalBottomSheet(
      context: context,
      backgroundColor: slate,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: ['👍', '❤️', '😂', '😮', '😢', '🙏']
                  .map((e) => GestureDetector(
                        onTap: () {
                          Navigator.pop(ctx);
                          react(m, e);
                        },
                        child: Text(e, style: const TextStyle(fontSize: 30)),
                      ))
                  .toList(),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.reply),
            title: const Text('Reply'),
            onTap: () {
              Navigator.pop(ctx);
              setState(() => replyTo = m);
            },
          ),
          ListTile(
            leading: const Icon(Icons.forward),
            title: const Text('Forward'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => ForwardScreen(m)));
            },
          ),
          if (kind == 'text')
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy'),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: m['body'].toString()));
                toast(context, 'Copy ho gaya');
              },
            ),
          if (mine)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Color(0xFFFF7A7A)),
              title: const Text('Sabke liye delete karo', style: TextStyle(color: Color(0xFFFF7A7A))),
              onTap: () {
                Navigator.pop(ctx);
                deleteMsg(m);
              },
            ),
        ]),
      ),
    );
  }

  Widget quote(Map<String, dynamic> m, bool mine) {
    final rid = m['reply_to'];
    if (rid == null) return const SizedBox.shrink();
    Map<String, dynamic>? o;
    for (final x in msgs) {
      if (x['id'] == rid) {
        o = x;
        break;
      }
    }
    final bar = mine ? slate : vanilla;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: mine ? const Color(0x22262323) : const Color(0x22FFFCD0), borderRadius: BorderRadius.circular(10)),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 3, color: bar),
          const SizedBox(width: 8),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(o == null ? '' : (o['sender'] == me ? 'Tum' : widget.name), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: mine ? slate : vanilla)),
              Text(o == null ? 'Message' : previewMsg(o), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: mine ? slate : mist)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget content(Map<String, dynamic> m, bool mine) {
    final kind = (m['kind'] ?? 'text').toString();
    final url = (m['media_url'] ?? '').toString();
    final body = (m['body'] ?? '').toString();
    final fg = mine ? ink : vanilla;
    final sub = mine ? slate : mist;
    final wd = MediaQuery.of(context).size.width * 0.6;
    if (m['deleted'] == true) {
      return Text('Ye message delete kar diya gaya', style: TextStyle(color: sub, fontStyle: FontStyle.italic, fontSize: 14.5));
    }
    Widget main;
    if (kind == 'image') {
      main = GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ImageView(url))),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.network(
            url,
            width: wd,
            height: 230,
            fit: BoxFit.cover,
            loadingBuilder: (c, child, p) => p == null ? child : SizedBox(width: wd, height: 230, child: const Center(child: CircularProgressIndicator(strokeWidth: 2))),
            errorBuilder: (_, __, ___) => SizedBox(width: wd, height: 120, child: const Center(child: Icon(Icons.broken_image))),
          ),
        ),
      );
    } else if (kind == 'video') {
      main = GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VideoScreen(url))),
        child: Container(
          width: wd,
          height: 150,
          decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(14)),
          child: Stack(children: [
            const Center(child: Icon(Icons.play_circle_fill, size: 54, color: vanilla)),
            Positioned(
              left: 10,
              bottom: 8,
              child: Text('${m['media_name'] ?? 'Video'}  ${fmtSize((m['media_size'] ?? 0) as int)}', style: const TextStyle(fontSize: 11.5, color: vanilla)),
            ),
          ]),
        ),
      );
    } else if (kind == 'voice') {
      main = VoicePlayer(key: ValueKey(url), url: url, dur: (m['duration'] ?? 0) as int, mine: mine);
    } else if (kind == 'file') {
      main = InkWell(
        onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.insert_drive_file, size: 34, color: fg),
          const SizedBox(width: 10),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((m['media_name'] ?? 'File').toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
              Text(fmtSize((m['media_size'] ?? 0) as int), style: TextStyle(fontSize: 12, color: sub)),
            ]),
          ),
        ]),
      );
    } else {
      return Text(body, style: TextStyle(color: fg, fontSize: 15.5));
    }
    if (body.isEmpty) return main;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      main,
      const SizedBox(height: 6),
      Text(body, style: TextStyle(color: fg, fontSize: 15.5)),
    ]);
  }

  Widget bubble(Map<String, dynamic> m) {
    final mine = m['sender'] == me;
    final del = m['deleted'] == true;
    final id = m['id'] as int;
    final rx = reacts[id];
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
        GestureDetector(
          onLongPress: del ? null : () => actions(m),
          child: Container(
            margin: EdgeInsets.only(top: 4, bottom: rx == null ? 4 : 0),
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
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
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              if (m['forwarded'] == true && !del)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('Forwarded', style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: mine ? slate : mist)),
                ),
              if (!del) quote(m, mine),
              content(m, mine),
              const SizedBox(height: 3),
              Align(
                alignment: Alignment.centerRight,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(fmtTime(m['created_at']), style: TextStyle(fontSize: 11, color: mine ? slate : mist)),
                  if (mine) ...[const SizedBox(width: 4), ticks(m['delivered'] == true, m['seen'] == true)],
                ]),
              ),
            ]),
          ),
        ),
        if (rx != null && !del)
          Container(
            margin: const EdgeInsets.only(bottom: 4, top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
            decoration: BoxDecoration(color: slate, borderRadius: BorderRadius.circular(12), border: Border.all(color: ink, width: 2)),
            child: Text(rx.entries.map((e) => e.value > 1 ? '${e.key} ${e.value}' : e.key).join(' '), style: const TextStyle(fontSize: 13)),
          ),
      ]),
    );
  }

  Widget replyBar() {
    final r = replyTo!;
    return Container(
      color: const Color(0xE0262323),
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
      child: Row(children: [
        Container(width: 3, height: 38, color: vanilla),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r['sender'] == me ? 'Tum' : widget.name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            Text(previewMsg(r), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: mist)),
          ]),
        ),
        IconButton(onPressed: () => setState(() => replyTo = null), icon: const Icon(Icons.close, size: 20)),
      ]),
    );
  }

  Widget inputRow() {
    final hasText = ctl.text.trim().isNotEmpty;
    return Container(
      color: const Color(0xE0262323),
      padding: const EdgeInsets.fromLTRB(6, 8, 12, 12),
      child: recording
          ? Row(children: [
              IconButton(onPressed: () => stopRec(send: false), icon: const Icon(Icons.delete_outline, color: Color(0xFFFF7A7A))),
              const Icon(Icons.circle, size: 12, color: Color(0xFFFF5A5A)),
              const SizedBox(width: 8),
              Text(fmtDur(Duration(seconds: recSecs)), style: const TextStyle(fontSize: 16)),
              const Spacer(),
              Material(
                color: vanilla,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => stopRec(send: true),
                  child: const Padding(padding: EdgeInsets.all(13), child: Icon(Icons.send_rounded, color: ink, size: 22)),
                ),
              ),
            ])
          : Row(children: [
              IconButton(onPressed: attach, icon: const Icon(Icons.attach_file, color: mist)),
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
                  onTap: hasText ? sendText : startRec,
                  child: Padding(padding: const EdgeInsets.all(13), child: Icon(hasText ? Icons.send_rounded : Icons.mic, color: ink, size: 22)),
                ),
              ),
            ]),
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
                Av(widget.name, url: widget.avatar, w: 38),
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
            if (uploading) const LinearProgressIndicator(minHeight: 2, color: vanilla, backgroundColor: slate),
            if (replyTo != null) replyBar(),
            inputRow(),
          ]),
        ),
      ),
    );
  }
}
