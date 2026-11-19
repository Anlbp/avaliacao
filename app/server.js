const express = require('express');

const API_URL = process.env.API_URL;
const app = express();
app.use(express.json());
app.use(express.static('public'));

app.get('/api/livros', async (_req, res) => {
  try {
    const r = await fetch(`${API_URL}/livros`);
    res.status(r.status).json(await r.json());
  } catch (err) {
    console.error(err);
    res.status(502).json({ erro: 'API indisponível' });
  }
});

app.post('/api/livros', async (req, res) => {
  try {
    const r = await fetch(`${API_URL}/livro`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(req.body),
    });
    res.status(r.status).json(await r.json());
  } catch (err) {
    console.error(err);
    res.status(502).json({ erro: 'API indisponível' });
  }
});

app.listen(3000, () => console.log('Web na porta 3000'));