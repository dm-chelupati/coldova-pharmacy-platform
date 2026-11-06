const express = require('express');
const path = require('path');
const app = express();
const port = process.env.PORT || 3000;
const gatewayUrl = (process.env.GATEWAY_URL || 'http://localhost:8080').replace(/\/$/, '');

app.get('/health', (req, res) => res.json({ status: 'healthy', service: 'frontend' }));

app.use(express.static(path.join(__dirname, 'public')));

async function proxyJson(res, path, method = 'GET') {
  try {
    const response = await fetch(`${gatewayUrl}${path}`, {
      method,
      headers: { accept: 'application/json' },
      signal: AbortSignal.timeout(7000)
    });
    const body = await response.text();
    res.status(response.status).type('application/json').send(body);
  } catch (err) {
    console.error(`Gateway request ${path} failed: ${err.message}`);
    res.status(502).json({
      errorCode: 'gateway_unreachable',
      detail: 'The pharmacy service is temporarily unavailable.'
    });
  }
}

app.get('/orders', async (req, res) => {
  await proxyJson(res, '/api/orders');
});

app.get('/payments', async (req, res) => {
  await proxyJson(res, '/api/payments');
});

app.get('/api/catalog', async (req, res) => {
  await proxyJson(res, '/api/catalog');
});

app.get('/api/benefits/:memberId', async (req, res) => {
  const memberId = Number(req.params.memberId);
  if (!Number.isInteger(memberId) || memberId <= 0) {
    return res.status(400).json({ errorCode: 'invalid_member_id' });
  }

  await proxyJson(res, `/api/benefits/${memberId}`);
});

app.get('/api/orders', async (req, res) => {
  await proxyJson(res, '/api/orders');
});

app.get('/api/payments', async (req, res) => {
  await proxyJson(res, '/api/payments');
});

app.post('/api/payments/process', async (req, res) => {
  await proxyJson(res, '/api/payments/process', 'POST');
});

app.listen(port, () => console.log(`Frontend on port ${port}`));
