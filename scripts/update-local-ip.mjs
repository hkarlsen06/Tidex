#!/usr/bin/env node
import { readFileSync, writeFileSync } from "fs";
import { networkInterfaces } from "os";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const configPath = join(__dirname, "../ios/App/App/capacitor.config.local.json");

function getLocalIP() {
  const nets = networkInterfaces();

  for (const name of Object.keys(nets)) {
    for (const net of nets[name]) {
      // Skip internal and non-IPv4 addresses
      if (net.family === "IPv4" && !net.internal) {
        // Prefer en0 (Wi-Fi on macOS) but accept any
        if (name === "en0") {
          return net.address;
        }
      }
    }
  }

  // Fallback: return first non-internal IPv4
  for (const name of Object.keys(nets)) {
    for (const net of nets[name]) {
      if (net.family === "IPv4" && !net.internal) {
        return net.address;
      }
    }
  }

  // Last resort
  return "127.0.0.1";
}

const localIP = getLocalIP();
const config = JSON.parse(readFileSync(configPath, "utf-8"));

config.server.url = `http://${localIP}:3000`;

writeFileSync(configPath, JSON.stringify(config, null, "\t") + "\n");

console.log(`Updated capacitor.config.local.json with IP: ${localIP}`);
