const express = require('express');
const mysql = require('mysql2/promise');

const pool = mysql.createPool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  waitForConnections: true,
  connectionLimit: 10,
});

const app = express();
app.use(express.json());

const handle = (fn) => (req, res) =>
  fn(req, res).catch((err) => {
    console.error(err);
    res.status(500).json({ erro: 'Erro interno' });
  });

app.get('/health', (_req, res) => res.json({ status: 'ok' }));

app.get('/livros', handle(async (_req, res) => {
  const [rows] = await pool.query(
    'SELECT id, titulo, autor, ano FROM livros ORDER BY id DESC'
  );
  res.json(rows);
}));

app.post('/livros', handle(async (req, res) => {
  const { titulo, autor, ano } = req.body ?? {};
  if (!titulo || !autor) {
    return res.status(400).json({ erro: 'titulo e autor são obrigatórios' });
  }
  const [result] = await pool.execute(
    'INSERT INTO livros (titulo, autor, ano) VALUES (?, ?, ?)',
    [titulo, autor, ano ?? null]
  );
  res.status(201).json({ id: result.insertId, titulo, autor, ano: ano ?? null });
}));

app.listen(3000, () => console.log('API na porta 3000'));