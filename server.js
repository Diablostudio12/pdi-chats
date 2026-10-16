const express = require('express');
const http = require('http');
const { WebSocketServer } = require('ws');
const { Pool } = require('pg');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');

const SECRET = process.env.JWT_SECRET || 'dev-secret-change-me';
const pool = new Pool({ connectionString: process.env.DATABASE_URL });
const app = express();
app.use(express.json({ limit: '100kb' }));

const online = new Map(); // username -> Set<ws>
const push = (u, data) => {
  const s = online.get(u);
  if (!s) return false;
  s.forEach((w) => { try { w.send(JSON.stringify(data)); } catch (e) {} });
  return s.size > 0;
};

async function init() {
  await pool.query(`CREATE TABLE IF NOT EXISTS users(
    username TEXT PRIMARY KEY, name TEXT NOT NULL, pass TEXT NOT NULL, created TIMESTAMPTZ DEFAULT now())`);
  await pool.query(`CREATE TABLE IF NOT EXISTS messages(
    id BIGSERIAL PRIMARY KEY, sender TEXT NOT NULL, receiver TEXT NOT NULL, body TEXT NOT NULL,
    created TIMESTAMPTZ DEFAULT now(), delivered BOOLEAN DEFAULT false, seen BOOLEAN DEFAULT false)`);
  await pool.query('CREATE INDEX IF NOT EXISTS m_pair ON messages(sender, receiver)');
}

const wrap = (fn) => (req, res) => fn(req, res).catch((e) => { console.error(e); res.status(500).json({ error: 'Server error' }); });

function auth(req, res, next) {
  const h = req.headers.authorization || '';
  try {
    req.user = jwt.verify(h.replace('Bearer ', ''), SECRET).u;
    next();
  } catch (e) {
    res.status(401).json({ error: 'Login dobara karo' });
  }
}

const token = (u) => jwt.sign({ u }, SECRET, { expiresIn: '180d' });

app.get('/', (req, res) => res.send('PDI CHATS server ok'));

app.post('/register', wrap(async (req, res) => {
  const username = String(req.body.username || '').toLowerCase().trim();
  const name = String(req.body.name || '').trim().slice(0, 40);
  const password = String(req.body.password || '');
  if (!/^[a-z0-9_]{3,20}$/.test(username)) return res.status(400).json({ error: 'Username 3-20 letters, number ya _ ka hona chahiye' });
  if (!name) return res.status(400).json({ error: 'Naam likho' });
  if (password.length < 6) return res.status(400).json({ error: 'Password kam se kam 6 akshar ka rakho' });
  const hash = await bcrypt.hash(password, 10);
  try {
    await pool.query('INSERT INTO users(username,name,pass) VALUES($1,$2,$3)', [username, name, hash]);
  } catch (e) {
    if (e.code === '23505') return res.status(409).json({ error: 'Ye username le liya gaya hai' });
    throw e;
  }
  res.json({ token: token(username), username, name });
}));

app.post('/login', wrap(async (req, res) => {
  const username = String(req.body.username || '').toLowerCase().trim();
  const r = await pool.query('SELECT * FROM users WHERE username=$1', [username]);
  const u = r.rows[0];
  if (!u || !(await bcrypt.compare(String(req.body.password || ''), u.pass))) return res.status(401).json({ error: 'Username ya password galat hai' });
  res.json({ token: token(u.username), username: u.username, name: u.name });
}));

app.post('/profile', auth, wrap(async (req, res) => {
  const name = String(req.body.name || '').trim().slice(0, 40);
  if (!name) return res.status(400).json({ error: 'Naam likho' });
  await pool.query('UPDATE users SET name=$1 WHERE username=$2', [name, req.user]);
  res.json({ ok: true });
}));

app.get('/users/search', auth, wrap(async (req, res) => {
  const q = String(req.query.q || '').toLowerCase().trim().replace(/[^a-z0-9_]/g, '');
  if (!q) return res.json([]);
  const r = await pool.query(
    'SELECT username,name FROM users WHERE username LIKE $1 AND username<>$2 ORDER BY username LIMIT 20',
    [q + '%', req.user]);
  res.json(r.rows);
}));

app.get('/chats', auth, wrap(async (req, res) => {
  const r = await pool.query(`
    WITH m AS (
      SELECT CASE WHEN sender=$1 THEN receiver ELSE sender END AS peer, *
      FROM messages WHERE sender=$1 OR receiver=$1)
    SELECT DISTINCT ON (peer) peer, body, created, sender, seen, delivered,
      (SELECT count(*) FROM messages x WHERE x.sender=m.peer AND x.receiver=$1 AND x.seen=false)::int AS unread,
      (SELECT name FROM users u WHERE u.username=m.peer) AS name
    FROM m ORDER BY peer, created DESC`, [req.user]);
  const rows = r.rows.map((x) => ({
    username: x.peer, name: x.name || x.peer, last: x.body, created: x.created,
    mine: x.sender === req.user, seen: x.seen, delivered: x.delivered, unread: x.unread,
  })).sort((a, b) => new Date(b.created) - new Date(a.created));
  res.json(rows);
}));

app.get('/messages/:peer', auth, wrap(async (req, res) => {
  const peer = req.params.peer;
  await pool.query('UPDATE messages SET delivered=true WHERE sender=$1 AND receiver=$2 AND delivered=false', [peer, req.user]);
  const r = await pool.query(
    `SELECT id,sender,body,created,delivered,seen FROM messages
     WHERE (sender=$1 AND receiver=$2) OR (sender=$2 AND receiver=$1)
     ORDER BY id DESC LIMIT 300`, [req.user, peer]);
  res.json(r.rows.reverse().map((x) => ({
    id: x.id, mine: x.sender === req.user, body: x.body, created: x.created, delivered: x.delivered, seen: x.seen,
  })));
}));

app.post('/messages', auth, wrap(async (req, res) => {
  const to = String(req.body.to || '').toLowerCase();
  const body = String(req.body.body || '').trim().slice(0, 4000);
  if (!body) return res.status(400).json({ error: 'Khali message' });
  const u = await pool.query('SELECT 1 FROM users WHERE username=$1', [to]);
  if (!u.rows.length) return res.status(404).json({ error: 'User nahi mila' });
  const isOn = online.has(to) && online.get(to).size > 0;
  const r = await pool.query(
    'INSERT INTO messages(sender,receiver,body,delivered) VALUES($1,$2,$3,$4) RETURNING id,created',
    [req.user, to, body, isOn]);
  push(to, { t: 'msg', from: req.user });
  res.json({ id: r.rows[0].id, created: r.rows[0].created });
}));

app.post('/seen/:peer', auth, wrap(async (req, res) => {
  const peer = req.params.peer;
  await pool.query('UPDATE messages SET seen=true, delivered=true WHERE sender=$1 AND receiver=$2 AND seen=false', [peer, req.user]);
  push(peer, { t: 'seen', by: req.user });
  res.json({ ok: true });
}));

const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: '/ws' });

wss.on('connection', (ws, req) => {
  let user;
  try {
    const t = new URL(req.url, 'http://x').searchParams.get('token');
    user = jwt.verify(t, SECRET).u;
  } catch (e) {
    return ws.close();
  }
  if (!online.has(user)) online.set(user, new Set());
  online.get(user).add(ws);
  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });
  ws.on('message', (raw) => {
    try {
      const m = JSON.parse(raw);
      if (m.t === 'typing' && m.to) push(String(m.to), { t: 'typing', from: user });
    } catch (e) {}
  });
  ws.on('close', () => {
    const s = online.get(user);
    if (s) { s.delete(ws); if (!s.size) online.delete(user); }
  });
});

setInterval(() => {
  wss.clients.forEach((w) => {
    if (!w.isAlive) return w.terminate();
    w.isAlive = false;
    w.ping();
  });
}, 30000);

const PORT = process.env.PORT || 3000;
init().then(() => server.listen(PORT, () => console.log('PDI CHATS server on ' + PORT)))
  .catch((e) => { console.error(e); process.exit(1); });
