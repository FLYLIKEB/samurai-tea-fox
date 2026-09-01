#!/usr/bin/env node
import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

const root = process.argv[2] ? resolve(process.argv[2]) : process.cwd();
const env = {
  ...loadDotEnv(await readText(resolve(root, ".env.local"))),
  ...loadDotEnv(await readText(resolve(root, ".env"))),
  ...process.env,
};

const baseUrl = (env.PIXELLAB_API_BASE_URL || "https://api.pixellab.ai/v2").replace(/\/+$/, "");
const apiKey = env.PIXELLAB_API_KEY;

if (!apiKey) {
  console.error("PIXELLAB_API_KEY가 없습니다. `.env.local` 또는 환경변수에 설정하세요.");
  process.exit(2);
}

const response = await fetch(`${baseUrl}/balance`, {
  headers: { Authorization: `Bearer ${apiKey}` },
});

if (response.status === 401) {
  console.error("PixelLab 인증 실패: API 토큰이 거부되었습니다.");
  process.exit(1);
}

if (!response.ok) {
  const text = await response.text();
  console.error(`PixelLab balance 확인 실패: HTTP ${response.status} ${text.slice(0, 200)}`);
  process.exit(1);
}

const body = await response.json();
const creditType = body?.credits?.type || "unknown";
const subscriptionType = body?.subscription?.type || "unknown";
const subscriptionStatus = body?.subscription?.status || "unknown";

console.log(
  `PixelLab 인증 확인 성공: /balance HTTP 200, credits=${creditType}, subscription=${subscriptionType}, status=${subscriptionStatus}`,
);

function loadDotEnv(contents) {
  return Object.fromEntries(
    contents
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter((line) => line && !line.startsWith("#") && line.includes("="))
      .map((line) => {
        const index = line.indexOf("=");
        return [line.slice(0, index).trim(), line.slice(index + 1).trim().replace(/^['"]|['"]$/g, "")];
      }),
  );
}

async function readText(file) {
  return existsSync(file) ? readFile(file, "utf8") : "";
}
