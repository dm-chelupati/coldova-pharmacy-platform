const http = require('http');

const port = Number(process.env.PORT || 8080);
const sqlTarget = new URL(process.env.MCP_TARGET || 'http://sql-mcp:5000');
const appApiTarget = new URL(process.env.APP_API_TARGET || 'http://benefits-api:5000');
const automationTarget = new URL(
  process.env.AUTOMATION_MCP_TARGET || 'http://sql-automation-mcp:5000'
);
const githubTarget = new URL(process.env.GITHUB_MCP_TARGET || 'http://github-mcp:8082');
const bearerToken = process.env.MCP_BEARER_TOKEN;
const githubToken = process.env.GITHUB_PERSONAL_ACCESS_TOKEN;

if (!bearerToken) {
  throw new Error('MCP_BEARER_TOKEN is required.');
}

if (!githubToken) {
  throw new Error('GITHUB_PERSONAL_ACCESS_TOKEN is required.');
}

const server = http.createServer((request, response) => {
  if (request.url === '/health') {
    response.writeHead(200, { 'content-type': 'application/json' });
    response.end(JSON.stringify({ status: 'healthy', service: 'sql-mcp-auth-proxy' }));
    return;
  }

  if (request.headers.authorization !== `Bearer ${bearerToken}`) {
    response.writeHead(401, { 'content-type': 'application/json' });
    response.end(JSON.stringify({ error: 'unauthorized' }));
    return;
  }

  const isGitHubRequest =
    request.url === '/github-mcp' || request.url.startsWith('/github-mcp/');
  const isAutomationRequest =
    request.url === '/automation-mcp' || request.url.startsWith('/automation-mcp/');
  const isAppApiRequest =
    request.url === '/api' || request.url.startsWith('/api/');
  const target = isGitHubRequest
    ? githubTarget
    : isAutomationRequest
      ? automationTarget
      : isAppApiRequest
        ? appApiTarget
        : sqlTarget;
  const upstreamPath = isGitHubRequest
    ? request.url.slice('/github-mcp'.length) || '/'
    : isAutomationRequest
      ? `/mcp${request.url.slice('/automation-mcp'.length)}`
      : request.url;
  const headers = { ...request.headers, host: target.host };
  delete headers['content-length'];

  if (isGitHubRequest) {
    headers.authorization = `Bearer ${githubToken}`;
    headers['x-mcp-toolsets'] = 'issues';
    headers['x-mcp-readonly'] = 'false';
  }

  const upstream = http.request({
    protocol: target.protocol,
    hostname: target.hostname,
    port: target.port,
    method: request.method,
    path: upstreamPath,
    headers
  }, upstreamResponse => {
    response.writeHead(upstreamResponse.statusCode || 502, upstreamResponse.headers);
    upstreamResponse.pipe(response);
  });

  upstream.on('error', error => {
    console.error(`MCP proxy upstream error: ${error.message}`);
    if (!response.headersSent) {
      response.writeHead(502, { 'content-type': 'application/json' });
    }
    response.end(JSON.stringify({ error: 'mcp_upstream_unavailable' }));
  });

  request.pipe(upstream);
});

server.requestTimeout = 0;
server.headersTimeout = 65000;
server.listen(port, '0.0.0.0', () => {
  console.log(`MCP authentication proxy listening on port ${port}`);
});
