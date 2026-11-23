// TCP relay: exposes the Windows-local Clash HTTP proxy to WSL.
//
// WSL2 (NAT mode) cannot reach 127.0.0.1 on the Windows host. This relay
// listens on the WSL virtual adapter only, so the distro can use it while the
// LAN cannot.

const net = require('net');
const os = require('os');

const LISTEN_PORT = Number(process.env.CDR_RELAY_PORT || 17897);
const TARGET_HOST = process.env.CDR_CLASH_HOST || '127.0.0.1';
const TARGET_PORT = Number(process.env.CDR_CLASH_PORT || 7897);

function wslHost() {
  const nets = os.networkInterfaces();
  for (const [name, addrs] of Object.entries(nets)) {
    if (!/wsl/i.test(name)) continue;
    for (const a of addrs || []) {
      if (a.family === 'IPv4' && !a.internal) return a.address;
    }
  }
  return '0.0.0.0';
}

const host = wslHost();

net.createServer((client) => {
  const upstream = net.connect({ host: TARGET_HOST, port: TARGET_PORT });
  client.pipe(upstream);
  upstream.pipe(client);
  client.on('error', () => upstream.destroy());
  upstream.on('error', () => client.destroy());
}).listen(LISTEN_PORT, host, () => {
  console.log(`relay listening on ${host}:${LISTEN_PORT} -> ${TARGET_HOST}:${TARGET_PORT}`);
});
