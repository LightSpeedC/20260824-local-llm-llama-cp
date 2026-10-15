// 指定した接尾辞の最新のログに行が増えたら、そのまま 1 行ずつ出す
import { readdirSync, readFileSync, statSync } from 'node:fs';

const dir = process.argv[2];
const suffix = process.argv[3];
const since = Number(process.argv[4]);
// 先頭から読み飛ばす行数（見張りを仕掛け直すとき、出した分を繰り返さない）
let seen = Number(process.argv[5] ?? 0);
let current = '';

function newest(): string {
	const files = readdirSync(dir)
		.filter((f) => f.endsWith(suffix))
		.map((f) => ({ f, t: statSync(`${dir}/${f}`).mtimeMs }))
		.filter((x) => x.t >= since)
		.sort((a, b) => b.t - a.t);
	return files.length ? `${dir}/${files[0].f}` : '';
}

setInterval(() => {
	const f = newest();
	if (!f) return;
	if (current && f !== current) seen = 0;
	current = f;
	const lines = readFileSync(f, 'utf8').split('\n').filter((l) => l.trim());
	for (; seen < lines.length; seen++) console.log(lines[seen]);
}, 20000);
