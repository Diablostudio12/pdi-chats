import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'main.dart';

const kRoles = ['admin', 'head', 'manager', 'casting_director', 'editor', 'member'];

String roleName(String r) => r == 'member' ? 'Normal member' : roleLabel(r);

Widget roleBadge(String r) {
  final l = roleLabel(r);
  if (l.isEmpty) return const SizedBox.shrink();
  return Container(
    margin: const EdgeInsets.only(left: 8),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: const Color(0x33FFFCD0), borderRadius: BorderRadius.circular(7)),
    child: Text(l, style: const TextStyle(fontSize: 10.5, color: vanilla, fontWeight: FontWeight.w600)),
  );
}

Widget pillField(String hint, {TextEditingController? c, ValueChanged<String>? onChanged, String? prefix, bool autofocus = false}) =>
    TextField(
      controller: c,
      onChanged: onChanged,
      autofocus: autofocus,
      autocorrect: false,
      decoration: InputDecoration(
        hintText: hint,
        prefixText: prefix,
        filled: true,
        fillColor: slate,
        hintStyle: const TextStyle(color: mist),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    );

Future<List<Map<String, dynamic>>> searchUsers(String q) async {
  final s = q.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
  if (s.isEmpty) return [];
  final d = await sb
      .from('profiles')
      .select('id,username,name,avatar_url')
      .ilike('username', '$s%')
      .neq('id', sb.auth.currentUser!.id)
      .limit(20);
  return List<Map<String, dynamic>>.from(d);
}

// ---------- join with invite code ----------
Future<void> joinWithCode(BuildContext context) async {
  final c = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: slate,
      title: const Text('Invite code'),
      content: TextField(controller: c, autofocus: true, autocorrect: false, decoration: const InputDecoration(hintText: 'jaise a1b2c3d4')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: mist))),
        TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Join')),
      ],
    ),
  );
  if (code == null || code.isEmpty) return;
  try {
    final r = await sb.rpc('join_by_code', params: {'p_code': code});
    Live.tick.value++;
    if (!context.mounted) return;
    final s = r.toString();
    toast(context, s == 'joined' ? 'Join ho gaye' : (s == 'requested' ? 'Request bhej di. Admin approve karega to join ho jaoge' : 'Tum pehle se member ho'));
  } catch (e) {
    if (context.mounted) toast(context, errText(e));
  }
}

// ---------- create group / community ----------
class CreateConvScreen extends StatefulWidget {
  final String type;
  final String? parentId;
  const CreateConvScreen({required this.type, this.parentId, super.key});
  @override
  State<CreateConvScreen> createState() => _CreateState();
}

class _CreateState extends State<CreateConvScreen> {
  final name = TextEditingController(), about = TextEditingController();
  bool approval = false, onlyAdmins = false, busy = false;
  List<Map<String, dynamic>> res = [];
  final List<Map<String, dynamic>> picked = [];

  @override
  void initState() {
    super.initState();
    onlyAdmins = widget.type == 'community';
  }

  Future<void> find(String q) async {
    try {
      final r = await searchUsers(q);
      if (mounted) setState(() => res = r);
    } catch (_) {}
  }

  Future<void> create() async {
    final n = name.text.trim();
    if (n.isEmpty) {
      toast(context, 'Naam likho');
      return;
    }
    setState(() => busy = true);
    try {
      final id = await sb.rpc('create_conversation', params: {
        'p_type': widget.type,
        'p_name': n,
        'p_about': about.text.trim(),
        'p_parent': widget.parentId,
        'p_approval': approval,
        'p_only_admins': onlyAdmins,
      });
      final cid = id.toString();
      if (picked.isNotEmpty) {
        await sb.rpc('add_members', params: {'p_conv': cid, 'p_users': picked.map((u) => u['id']).toList()});
      }
      final c = await sb.from('conversations').select().eq('id', cid).single();
      if (!mounted) return;
      Live.tick.value++;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ChatScreen(conv: Map<String, dynamic>.from(c))));
    } catch (e) {
      if (mounted) toast(context, errText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final comm = widget.type == 'community';
    return Scaffold(
      appBar: AppBar(backgroundColor: ink, title: Text(comm ? 'Nayi community' : 'Naya group')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        pillField('Naam', c: name),
        const SizedBox(height: 12),
        pillField('About (optional)', c: about),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: approval,
          onChanged: (v) => setState(() => approval = v),
          activeColor: vanilla,
          title: const Text('Join approval'),
          subtitle: const Text('Naye log admin ke approve karne ke baad hi judenge', style: TextStyle(color: mist, fontSize: 12.5)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: onlyAdmins,
          onChanged: (v) => setState(() => onlyAdmins = v),
          activeColor: vanilla,
          title: Text(comm ? 'Sirf admin roles announcement bhejein' : 'Sirf admin roles message bhejein'),
          subtitle: const Text('Casting Director, Editor, Manager, Head, Admin, Owner', style: TextStyle(color: mist, fontSize: 12.5)),
        ),
        const SizedBox(height: 14),
        const Text('Members add karo (username se)', style: TextStyle(color: mist)),
        const SizedBox(height: 8),
        pillField('username', onChanged: find, prefix: '@'),
        if (picked.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              spacing: 8,
              children: picked
                  .map((u) => Chip(
                        label: Text(u['name'].toString()),
                        backgroundColor: slate,
                        onDeleted: () => setState(() => picked.remove(u)),
                      ))
                  .toList(),
            ),
          ),
        ...res.map((u) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Av(u['name'].toString(), url: u['avatar_url']?.toString(), w: 38),
              title: Text(u['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('@${u['username']}', style: const TextStyle(color: mist)),
              trailing: const Icon(Icons.add_circle_outline),
              onTap: () {
                if (!picked.any((p) => p['id'] == u['id'])) setState(() => picked.add(u));
              },
            )),
        const SizedBox(height: 22),
        FilledButton(
          onPressed: busy ? null : create,
          style: FilledButton.styleFrom(backgroundColor: vanilla, foregroundColor: ink, padding: const EdgeInsets.symmetric(vertical: 16)),
          child: Text(busy ? 'Ban raha hai...' : 'Banao', style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

// ---------- add members later ----------
class AddMembersScreen extends StatefulWidget {
  final String convId;
  const AddMembersScreen(this.convId, {super.key});
  @override
  State<AddMembersScreen> createState() => _AddState();
}

class _AddState extends State<AddMembersScreen> {
  List<Map<String, dynamic>> res = [];
  final Set<String> added = {};

  Future<void> find(String q) async {
    try {
      final r = await searchUsers(q);
      if (mounted) setState(() => res = r);
    } catch (_) {}
  }

  Future<void> add(Map<String, dynamic> u) async {
    try {
      await sb.rpc('add_members', params: {'p_conv': widget.convId, 'p_users': [u['id']]});
      if (mounted) setState(() => added.add(u['id'].toString()));
    } catch (e) {
      if (mounted) toast(context, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: ink, title: const Text('Members add karo')),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: pillField('username', onChanged: find, prefix: '@', autofocus: true)),
        Expanded(
          child: ListView.builder(
            itemCount: res.length,
            itemBuilder: (_, i) {
              final u = res[i];
              final done = added.contains(u['id'].toString());
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 2),
                leading: Av(u['name'].toString(), url: u['avatar_url']?.toString(), w: 38),
                title: Text(u['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('@${u['username']}', style: const TextStyle(color: mist)),
                trailing: Icon(done ? Icons.check_circle : Icons.add_circle_outline, color: done ? vanilla : mist),
                onTap: done ? null : () => add(u),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ---------- group / community info ----------
class ConvInfoScreen extends StatefulWidget {
  final String convId;
  const ConvInfoScreen(this.convId, {super.key});
  @override
  State<ConvInfoScreen> createState() => _InfoState();
}

class _InfoState extends State<ConvInfoScreen> {
  Map<String, dynamic>? c;
  List<Map<String, dynamic>> members = [], reqs = [];
  String myRole = 'member';
  bool busy = false;
  String get me => sb.auth.currentUser!.id;
  int get myRank => roleRank(myRole);
  bool get manager => myRank >= 60;

  @override
  void initState() {
    super.initState();
    load();
  }

  Map<String, dynamic> person(Map<String, dynamic> r) {
    final pr = r['profiles'] is Map ? Map<String, dynamic>.from(r['profiles'] as Map) : <String, dynamic>{};
    return {
      'id': r['user_id'].toString(),
      'role': (r['role'] ?? 'member').toString(),
      'name': (pr['name'] ?? pr['username'] ?? 'Member').toString(),
      'username': (pr['username'] ?? '').toString(),
      'avatar': pr['avatar_url']?.toString(),
    };
  }

  Future<void> load() async {
    try {
      final cd = await sb.from('conversations').select().eq('id', widget.convId).single();
      final ms = await sb.from('conv_members').select('user_id, role, profiles(username,name,avatar_url)').eq('conv_id', widget.convId);
      final list = <Map<String, dynamic>>[];
      String mr = 'member';
      for (final r in List<Map<String, dynamic>>.from(ms)) {
        list.add(person(r));
        if (r['user_id'] == me) mr = r['role'].toString();
      }
      list.sort((a, b) {
        final d = roleRank(b['role'].toString()).compareTo(roleRank(a['role'].toString()));
        return d != 0 ? d : a['name'].toString().compareTo(b['name'].toString());
      });
      final rq = <Map<String, dynamic>>[];
      if (roleRank(mr) >= 60) {
        final rs = await sb.from('join_requests').select('user_id, profiles(username,name,avatar_url)').eq('conv_id', widget.convId);
        for (final r in List<Map<String, dynamic>>.from(rs)) {
          rq.add(person(r));
        }
      }
      if (!mounted) return;
      setState(() {
        c = Map<String, dynamic>.from(cd);
        members = list;
        reqs = rq;
        myRole = mr;
      });
    } catch (_) {}
  }

  Future<void> act(Future<void> Function() f) async {
    setState(() => busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) toast(context, errText(e));
    } finally {
      if (mounted) setState(() => busy = false);
      await load();
    }
  }

  Future<void> edit(String field, String title, int max) async {
    final ctl = TextEditingController(text: (c?[field] ?? '').toString());
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: slate,
        title: Text(title),
        content: TextField(controller: ctl, maxLength: max, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: mist))),
          TextButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (v == null || (field == 'name' && v.isEmpty)) return;
    await act(() async {
      await sb.rpc('update_conv', params: {'p_conv': widget.convId, 'p_$field': v});
    });
  }

  Future<void> changeAvatar() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
    if (x == null) return;
    await act(() async {
      final url = await uploadFile(File(x.path), x.name);
      await sb.rpc('update_conv', params: {'p_conv': widget.convId, 'p_avatar': url});
    });
  }

  void memberSheet(Map<String, dynamic> m) {
    if (!manager || m['id'] == me || roleRank(m['role'].toString()) >= myRank) return;
    final roles = kRoles.where((r) => roleRank(r) < myRank).toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: slate,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 6),
              child: Align(alignment: Alignment.centerLeft, child: Text('${m['name']} ka role', style: const TextStyle(fontFamily: 'serif', fontSize: 24, fontWeight: FontWeight.w700))),
            ),
            ...roles.map((r) => ListTile(
                  title: Text(roleName(r)),
                  trailing: m['role'] == r ? const Icon(Icons.check, color: vanilla) : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    act(() async {
                      await sb.rpc('set_role', params: {'p_conv': widget.convId, 'p_user': m['id'], 'p_role': r});
                    });
                  },
                )),
            ListTile(
              leading: const Icon(Icons.person_remove, color: Color(0xFFFF7A7A)),
              title: const Text('Hata do', style: TextStyle(color: Color(0xFFFF7A7A))),
              onTap: () {
                Navigator.pop(ctx);
                act(() async {
                  await sb.rpc('remove_member', params: {'p_conv': widget.convId, 'p_user': m['id']});
                });
              },
            ),
          ]),
        ),
      ),
    );
  }

  Widget tile(IconData i, String label, String value, VoidCallback? f) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
        leading: Icon(i, color: mist),
        title: Text(label, style: const TextStyle(color: mist, fontSize: 13)),
        subtitle: Text(value, style: const TextStyle(fontSize: 16)),
        trailing: f == null ? null : const Icon(Icons.edit, size: 18, color: mist),
        onTap: f,
      );

  Widget heading(String t, {Widget? action}) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 16, 6),
        child: Row(children: [
          Expanded(child: Text(t, style: const TextStyle(color: mist, fontWeight: FontWeight.w700))),
          if (action != null) action,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final cv = c;
    if (cv == null) {
      return Scaffold(appBar: AppBar(backgroundColor: ink), body: const Center(child: CircularProgressIndicator(color: vanilla)));
    }
    final isComm = cv['type'] == 'community';
    final nm = cv['name'].toString();
    final about = (cv['about'] ?? '').toString();
    return Scaffold(
      appBar: AppBar(backgroundColor: ink, title: Text(isComm ? 'Community info' : 'Group info')),
      body: ListView(children: [
        if (busy) const LinearProgressIndicator(minHeight: 2, color: vanilla, backgroundColor: slate),
        const SizedBox(height: 18),
        Center(child: GestureDetector(onTap: manager && !busy ? changeAvatar : null, child: Av(nm, url: cv['avatar_url']?.toString(), w: 110))),
        const SizedBox(height: 14),
        Center(child: Text(nm, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'serif', fontSize: 28, fontWeight: FontWeight.w700))),
        const SizedBox(height: 4),
        Center(child: Text('${members.length} members  |  Tumhara role: ${roleName(myRole)}', style: const TextStyle(color: mist, fontSize: 13))),
        const SizedBox(height: 10),
        tile(Icons.info_outline, 'About', about.isEmpty ? 'Kuch nahi likha' : about, manager ? () => edit('about', 'About badlo', 200) : null),
        if (manager) tile(Icons.edit_note, 'Naam', nm, () => edit('name', 'Naam badlo', 40)),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          value: cv['approval_required'] == true,
          onChanged: manager
              ? (v) => act(() async {
                    await sb.rpc('update_conv', params: {'p_conv': widget.convId, 'p_approval': v});
                  })
              : null,
          activeColor: vanilla,
          title: const Text('Join approval'),
          subtitle: const Text('Naye log admin approve kare tabhi jud payenge', style: TextStyle(color: mist, fontSize: 12.5)),
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          value: cv['only_admins_post'] == true,
          onChanged: manager
              ? (v) => act(() async {
                    await sb.rpc('update_conv', params: {'p_conv': widget.convId, 'p_only_admins': v});
                  })
              : null,
          activeColor: vanilla,
          title: Text(isComm ? 'Sirf admin roles announcement bhejein' : 'Sirf admin roles message bhejein'),
          subtitle: const Text('Casting Director, Editor, Manager, Head, Admin, Owner', style: TextStyle(color: mist, fontSize: 12.5)),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
          leading: const Icon(Icons.vpn_key, color: mist),
          title: const Text('Invite code', style: TextStyle(color: mist, fontSize: 13)),
          subtitle: Text((cv['invite_code'] ?? '').toString(), style: const TextStyle(fontSize: 18, letterSpacing: 2)),
          trailing: IconButton(
            icon: const Icon(Icons.copy, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: (cv['invite_code'] ?? '').toString()));
              toast(context, 'Code copy ho gaya');
            },
          ),
        ),
        if (isComm)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
            leading: const Icon(Icons.groups, color: mist),
            title: const Text('Community ke groups'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CommunityGroupsScreen(cv))),
          ),
        if (manager && reqs.isNotEmpty) ...[
          heading('Join requests (${reqs.length})'),
          ...reqs.map((r) => ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
                leading: Av(r['name'].toString(), url: r['avatar'], w: 38),
                title: Text(r['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('@${r['username']}', style: const TextStyle(color: mist)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFFFF7A7A)),
                    onPressed: () => act(() async {
                      await sb.rpc('review_request', params: {'p_conv': widget.convId, 'p_user': r['id'], 'p_approve': false});
                    }),
                  ),
                  IconButton(
                    icon: const Icon(Icons.check_circle, color: vanilla),
                    onPressed: () => act(() async {
                      await sb.rpc('review_request', params: {'p_conv': widget.convId, 'p_user': r['id'], 'p_approve': true});
                    }),
                  ),
                ]),
              )),
        ],
        heading(
          'Members (${members.length})',
          action: manager
              ? TextButton.icon(
                  onPressed: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => AddMembersScreen(widget.convId)));
                    load();
                  },
                  icon: const Icon(Icons.person_add, size: 18),
                  label: const Text('Add'),
                )
              : null,
        ),
        ...members.map((m) => ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
              leading: Av(m['name'].toString(), url: m['avatar'], w: 38),
              title: Row(children: [
                Flexible(child: Text(m['name'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                roleBadge(m['role'].toString()),
              ]),
              subtitle: Text('@${m['username']}', style: const TextStyle(color: mist)),
              trailing: m['id'] == me ? const Text('Tum', style: TextStyle(color: mist)) : null,
              onTap: () => memberSheet(m),
            )),
        const SizedBox(height: 16),
        if (myRole == 'owner')
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text('Tum owner ho, isliye chhod nahi sakte.', style: TextStyle(color: mist, fontSize: 13)),
          )
        else
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: const Icon(Icons.logout, color: Color(0xFFFF7A7A)),
            title: Text(isComm ? 'Community chhodo' : 'Group chhodo', style: const TextStyle(color: Color(0xFFFF7A7A))),
            onTap: () => act(() async {
              await sb.rpc('leave_conv', params: {'p_conv': widget.convId});
              Live.tick.value++;
              if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
            }),
          ),
        const SizedBox(height: 30),
      ]),
    );
  }
}

// ---------- groups inside a community ----------
class CommunityGroupsScreen extends StatefulWidget {
  final Map<String, dynamic> comm;
  const CommunityGroupsScreen(this.comm, {super.key});
  @override
  State<CommunityGroupsScreen> createState() => _CommGroupsState();
}

class _CommGroupsState extends State<CommunityGroupsScreen> {
  List<Map<String, dynamic>> groups = [];
  Set<String> joined = {};
  String commRole = 'member';
  String get me => sb.auth.currentUser!.id;
  String get cid => widget.comm['id'].toString();

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final g = await sb.from('conversations').select().eq('parent_id', cid).order('created_at');
      final m = await sb.from('conv_members').select('conv_id, role').eq('user_id', me);
      final js = <String>{};
      var cr = 'member';
      for (final r in List<Map<String, dynamic>>.from(m)) {
        js.add(r['conv_id'].toString());
        if (r['conv_id'].toString() == cid) cr = r['role'].toString();
      }
      if (!mounted) return;
      setState(() {
        groups = List<Map<String, dynamic>>.from(g);
        joined = js;
        commRole = cr;
      });
    } catch (_) {}
  }

  Future<void> join(Map<String, dynamic> g) async {
    try {
      final r = await sb.rpc('request_join', params: {'p_conv': g['id']});
      Live.tick.value++;
      if (mounted) {
        final s = r.toString();
        toast(context, s == 'joined' ? 'Join ho gaye' : (s == 'requested' ? 'Request bhej di. Admin approve karega' : 'Tum pehle se member ho'));
      }
    } catch (e) {
      if (mounted) toast(context, errText(e));
    }
    load();
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = roleRank(commRole) >= 60;
    return Scaffold(
      appBar: AppBar(backgroundColor: ink, title: Text('${widget.comm['name']} ke groups')),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              backgroundColor: vanilla,
              foregroundColor: ink,
              icon: const Icon(Icons.group_add),
              label: const Text('Naya group', style: TextStyle(fontWeight: FontWeight.w700)),
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => CreateConvScreen(type: 'group', parentId: cid)));
                load();
              },
            )
          : null,
      body: groups.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('Is community me abhi koi group nahi.', style: TextStyle(color: mist))))
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: groups.length,
              itemBuilder: (_, i) {
                final g = groups[i];
                final nm = g['name'].toString();
                final isIn = joined.contains(g['id'].toString());
                final about = (g['about'] ?? '').toString();
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
                  leading: Av(nm, url: g['avatar_url']?.toString()),
                  title: Text(nm, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    [if (about.isNotEmpty) about, if (g['approval_required'] == true) 'Approval chahiye'].join('  |  '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: mist, fontSize: 13),
                  ),
                  trailing: isIn
                      ? TextButton(
                          onPressed: () async {
                            await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(conv: g)));
                            load();
                          },
                          child: const Text('Open'),
                        )
                      : FilledButton(
                          onPressed: () => join(g),
                          style: FilledButton.styleFrom(backgroundColor: vanilla, foregroundColor: ink),
                          child: const Text('Join'),
                        ),
                  onTap: isIn
                      ? () async {
                          await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(conv: g)));
                          load();
                        }
                      : null,
                );
              },
            ),
    );
  }
}
