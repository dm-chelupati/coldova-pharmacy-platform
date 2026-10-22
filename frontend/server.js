const express = require('express');
const app = express();
const port = process.env.PORT || 3000;
const gatewayUrl = process.env.GATEWAY_URL || 'http://localhost:8080';

app.get('/health', (req, res) => res.json({ status: 'healthy', service: 'frontend' }));

app.get('/', (req, res) => res.json({
  service: 'Coldova Pharmacy Operations',
  gateway: gatewayUrl,
  endpoints: ['/orders', '/payments', '/health']
}));

app.get('/orders', async (req, res) => {
  try {
    const r = await fetch(`${gatewayUrl}/api/orders`);
    if (!r.ok) throw new Error(`Gateway returned ${r.status}`);
    res.json(await r.json());
  } catch (err) {
    console.error(`Gateway error: ${err.message}`);
    res.status(502).json({ error: 'Gateway unreachable', detail: err.message });
  }
});

app.get('/payments', async (req, res) => {
  try {
    const r = await fetch(`${gatewayUrl}/api/payments`);
    if (!r.ok) throw new Error(`Gateway returned ${r.status}`);
    res.json(await r.json());
  } catch (err) {
    console.error(`Gateway error: ${err.message}`);
    res.status(502).json({ error: 'Gateway unreachable', detail: err.message });
  }
});

app.listen(port, () => console.log(`Frontend on port ${port}`));
