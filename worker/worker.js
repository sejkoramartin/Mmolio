// Cloudflare Worker: přijímač glykemie z xDrip4iOS + displej
//
// Worker se tváří jako Nightscout server. xDrip4iOS do něj nahrává naměřené
// hodnoty (push), worker si poslední z nich drží v KV a servíruje ji displeji
// na iPhonu i rozšíření pro GNOME přes /api/glucose.
//
// Proč takhle: odpadá dotazování neveřejných API výrobců (Abbott, Dexcom),
// se kterými jsme se za měsíc třikrát položili, a odpadá i provozování
// vlastního Nightscoutu s databází.
//
// Nastavení v xDrip4iOS (Settings -> Nightscout):
//   URL         https://glykemie.VASE-JMENO.workers.dev
//   API_SECRET  hodnota secretu NIGHTSCOUT_API_SECRET (min. 12 znaků)
//
// Ověřeno proti zdrojovému kódu xDrip4iOS (NightscoutSyncManager.swift,
// BgReading+Nightscout.swift): nahrává na /api/v1/entries s hlavičkou
// api-secret = SHA-1 otisk tajemství, spojení testuje na
// /api/v1/experiments/test.

const KEY_LATEST = "ns_latest";

// Nightscout "direction" -> co vydáváme klientům.
//  - trendArrow drží starou pětistupňovou škálu (1..5) kvůli zpětné
//    kompatibilitě s displejem na iPhonu a s rozšířením pro GNOME
//  - trendAngle je přesnější úhel pro budoucí klienty (0 = doprava)
const TRENDS = {
	DoubleUp: { arrow: 5, symbol: "↑↑", angle: -90 },
	SingleUp: { arrow: 4, symbol: "↑", angle: -60 },
	FortyFiveUp: { arrow: 4, symbol: "↗", angle: -45 },
	Flat: { arrow: 3, symbol: "→", angle: 0 },
	FortyFiveDown: { arrow: 2, symbol: "↘", angle: 45 },
	SingleDown: { arrow: 2, symbol: "↓", angle: 60 },
	DoubleDown: { arrow: 1, symbol: "↓↓", angle: 90 },
};

const UNKNOWN_TREND = { arrow: 0, symbol: "?", angle: 0 };

function corsHeaders() {
	return {
		"access-control-allow-origin": "*",
		"access-control-allow-methods": "GET, POST, PUT, DELETE, OPTIONS",
		"access-control-allow-headers": "content-type, api-secret",
	};
}

function json(data, status = 200) {
	return new Response(JSON.stringify(data), {
		status,
		headers: { "content-type": "application/json", ...corsHeaders() },
	});
}

async function resolveSecret(binding) {
	if (binding == null) return "";
	if (typeof binding === "string") return binding;
	if (typeof binding.get === "function") return await binding.get();
	return String(binding);
}

async function sha1Hex(text) {
	const data = new TextEncoder().encode(text);
	const hash = await crypto.subtle.digest("SHA-1", data);
	return [...new Uint8Array(hash)]
		.map((b) => b.toString(16).padStart(2, "0"))
		.join("");
}

// Porovnání nezávislé na délce shodného prefixu.
function safeEqual(a, b) {
	if (a.length !== b.length) return false;
	let diff = 0;
	for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
	return diff === 0;
}

// xDrip posílá SHA-1 otisk tajemství, nikdy ne tajemství samotné.
async function isAuthorized(request, env) {
	const secret = (await resolveSecret(env.NIGHTSCOUT_API_SECRET)).trim();
	if (!secret) {
		throw new Error(
			"Chybí NIGHTSCOUT_API_SECRET (binding není nastavený nebo je prázdný)"
		);
	}

	const url = new URL(request.url);
	const provided = (
		request.headers.get("api-secret") ||
		url.searchParams.get("secret") ||
		""
	)
		.trim()
		.toLowerCase();
	if (!provided) return false;

	return safeEqual(provided, await sha1Hex(secret));
}

function normalizeDirection(direction) {
	if (typeof direction !== "string") return null;
	// Nightscout používá i tvary se zarážkou/mezerou ("NOT COMPUTABLE")
	return direction.replace(/[\s_-]/g, "").toLowerCase();
}

function resolveTrend(direction) {
	const normalized = normalizeDirection(direction);
	if (!normalized) return UNKNOWN_TREND;

	for (const [name, trend] of Object.entries(TRENDS)) {
		if (name.toLowerCase() === normalized) return trend;
	}
	return UNKNOWN_TREND;
}

// Z nahrané dávky vybereme nejnovější platné měření glykemie.
function newestSgv(entries) {
	let newest = null;
	for (const entry of entries) {
		if (!entry || typeof entry !== "object") continue;
		if ((entry.type ?? "sgv") !== "sgv") continue;

		const sgv = Number(entry.sgv);
		const date = Number(entry.date);
		if (!Number.isFinite(sgv) || sgv <= 0) continue;
		if (!Number.isFinite(date) || date <= 0) continue;

		if (!newest || date > newest.date) {
			newest = {
				sgv: Math.round(sgv),
				date,
				direction: entry.direction ?? null,
				device: entry.device ?? null,
			};
		}
	}
	return newest;
}

async function storeIfNewer(env, reading) {
	const stored = await env.TOKEN_KV.get(KEY_LATEST, { type: "json" });
	// Dávka může obsahovat i starší doplněná měření – nikdy jimi
	// nepřepisujeme novější hodnotu.
	if (stored && Number(stored.date) >= reading.date) return stored;

	await env.TOKEN_KV.put(KEY_LATEST, JSON.stringify(reading));
	return reading;
}

function toGlucoseResponse(reading) {
	const mgdl = reading.sgv;
	const mmol = Math.round((mgdl / 18.0182) * 10) / 10;
	const trend = resolveTrend(reading.direction);

	return {
		mgdl,
		mmol,
		trendArrow: trend.arrow,
		trendSymbol: trend.symbol,
		trendAngle: trend.angle,
		trendName: reading.direction ?? null,
		timestamp: new Date(reading.date).toISOString(),
		device: reading.device ?? null,
		source: "xdrip",
	};
}

// ---- Nightscout API, jen to, co xDrip4iOS opravdu volá ----

async function handleEntriesUpload(request, env) {
	let body;
	try {
		body = await request.json();
	} catch (e) {
		return json({ error: "Tělo požadavku není platný JSON" }, 400);
	}

	const entries = Array.isArray(body) ? body : [body];
	const reading = newestSgv(entries);

	if (!reading) {
		// Dávka bez měření glykemie (např. jen kalibrace) není chyba.
		return json([]);
	}

	await storeIfNewer(env, reading);

	// Nightscout vrací uložené záznamy zpět.
	return json(entries);
}

async function handleEntriesDownload(env, url) {
	const stored = await env.TOKEN_KV.get(KEY_LATEST, { type: "json" });
	if (!stored) return json([]);

	const count = Number(url.searchParams.get("count") || "1");
	const since = Number(url.searchParams.get("find[date][$gte]") || "0");
	if (Number.isFinite(since) && since > 0 && stored.date < since) return json([]);

	const entry = {
		_id: String(stored.date),
		device: stored.device ?? "xDrip",
		date: stored.date,
		dateString: new Date(stored.date).toISOString(),
		sysTime: new Date(stored.date).toISOString(),
		type: "sgv",
		sgv: stored.sgv,
		direction: stored.direction ?? "NONE",
	};

	return json(count >= 1 ? [entry] : []);
}

async function handleGlucose(env) {
	const stored = await env.TOKEN_KV.get(KEY_LATEST, { type: "json" });
	if (!stored) {
		return json(
			{
				error:
					"Zatím nedorazilo žádné měření. Zkontroluj v xDrip4iOS nahrávání " +
					"do Nightscoutu (URL a API_SECRET).",
			},
			503
		);
	}
	return json(toGlucoseResponse(stored));
}

export default {
	async fetch(request, env) {
		const url = new URL(request.url);
		const path = url.pathname;

		if (request.method === "OPTIONS") {
			return new Response(null, { headers: corsHeaders() });
		}

		// Displej a rozšíření – beze změny kontraktu.
		if (path === "/api/glucose") {
			try {
				return await handleGlucose(env);
			} catch (err) {
				return json({ error: String(err) }, 500);
			}
		}

		if (path.startsWith("/api/v1/")) {
			try {
				if (!(await isAuthorized(request, env))) {
					return json({ status: 401, message: "Unauthorized" }, 401);
				}
			} catch (err) {
				return json({ error: String(err) }, 500);
			}

			// Test spojení z xDrip4iOS.
			if (path === "/api/v1/experiments/test") {
				return json({ status: 200, message: "OK" });
			}

			if (path === "/api/v1/entries" || path === "/api/v1/entries.json") {
				if (request.method === "POST") return handleEntriesUpload(request, env);
				if (request.method === "GET") return handleEntriesDownload(env, url);
				// DELETE a spol. tiše potvrdíme, ať xDrip nehlásí chybu
				return json([]);
			}

			if (path === "/api/v1/entries/sgv.json") {
				return handleEntriesDownload(env, url);
			}

			if (path === "/api/v1/status" || path === "/api/v1/status.json") {
				return json({
					status: "ok",
					name: "glykemie",
					apiEnabled: true,
					careportalEnabled: false,
					settings: { units: "mmol" },
				});
			}

			// Léčebné záznamy, stav zařízení a profil neukládáme, ale musíme
			// odpovědět úspěchem – jinak xDrip hlásí chyby nahrávání.
			if (
				path.startsWith("/api/v1/treatments") ||
				path.startsWith("/api/v1/devicestatus") ||
				path.startsWith("/api/v1/profile")
			) {
				return json([]);
			}

			return json({ status: 404, message: "Not found" }, 404);
		}

		// Vše ostatní (index.html, ...) servíruje static assets binding.
		return env.ASSETS.fetch(request);
	},
};
