"""Build a self-contained HTML report from the SonarQube web API.

Usage: html-report.py <base_url> <project_key> <out_file>   (token in env SONAR_TOKEN)
"""
import base64, html, json, os, sys, urllib.parse, urllib.request
from datetime import datetime

base, key, out = sys.argv[1].rstrip("/"), sys.argv[2], sys.argv[3]
auth = "Basic " + base64.b64encode((os.environ["SONAR_TOKEN"] + ":").encode()).decode()


def get(path, **params):
    url = f"{base}/api/{path}?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"Authorization": auth})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def safe(fn, default):
    try:
        return fn()
    except Exception:
        return default


gate = safe(lambda: get("qualitygates/project_status", projectKey=key)["projectStatus"], {"status": "UNKNOWN", "conditions": []})
metrics = "ncloc,coverage,bugs,vulnerabilities,code_smells,security_hotspots,duplicated_lines_density,reliability_rating,security_rating,sqale_rating,sqale_index"
measures = {m["metric"]: m.get("value", "") for m in safe(lambda: get("measures/component", component=key, metricKeys=metrics)["component"]["measures"], [])}

issues, page = [], 1
while True:
    d = safe(lambda: get("issues/search", componentKeys=key, resolved="false", ps=500, p=page), {"issues": [], "paging": {"total": 0}})
    issues += d["issues"]
    if len(issues) >= d["paging"]["total"] or not d["issues"] or page >= 20:
        break
    page += 1
hotspots = safe(lambda: get("hotspots/search", projectKey=key, ps=500)["hotspots"], [])

rating = {"1.0": "A", "2.0": "B", "3.0": "C", "4.0": "D", "5.0": "E"}
sev_order = {"BLOCKER": 0, "CRITICAL": 1, "MAJOR": 2, "MINOR": 3, "INFO": 4}
issues.sort(key=lambda i: (sev_order.get(i["severity"], 9), i["component"], i.get("line", 0)))
e = html.escape


def tile(label, value, sub=""):
    return f'<div class="tile"><div class="lbl">{e(label)}</div><div class="val">{e(str(value))}</div><div class="sub">{e(sub)}</div></div>'


def pct(name):
    v = measures.get(name)
    return f"{float(v):.1f}%" if v not in (None, "") else "n/a"


def rate(name):
    return rating.get(measures.get(name, ""), "n/a")


counts = {}
for i in issues:
    counts[i["severity"]] = counts.get(i["severity"], 0) + 1
status = gate.get("status", "UNKNOWN")
cond_rows = "".join(
    f'<tr><td>{e(c["metricKey"])}</td><td>{e(c["status"])}</td><td>{e(str(c.get("actualValue", "")))}</td><td>{e(c.get("comparator", ""))} {e(str(c.get("errorThreshold", "")))}</td></tr>'
    for c in gate.get("conditions", [])
) or '<tr><td colspan="4">No conditions</td></tr>'
issue_rows = "".join(
    f'<tr><td class="sev {e(i["severity"])}">{e(i["severity"])}</td><td>{e(i["type"])}</td>'
    f'<td>{e(i["component"].split(":", 1)[-1])}:{e(str(i.get("line", "-")))}</td><td>{e(i["message"])}</td><td>{e(i["rule"])}</td></tr>'
    for i in issues
) or '<tr><td colspan="5">No open issues</td></tr>'
hot_rows = "".join(
    f'<tr><td>{e(h.get("vulnerabilityProbability", ""))}</td><td>{e(h["component"].split(":", 1)[-1])}:{e(str(h.get("line", "-")))}</td><td>{e(h["message"])}</td></tr>'
    for h in hotspots
) or '<tr><td colspan="3">No security hotspots</td></tr>'

page_html = f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><title>{e(key)} Sonar report</title>
<style>
body{{font:14px/1.5 -apple-system,Segoe UI,sans-serif;margin:0;background:#f6f7fb;color:#1d2433}}
header{{background:#fff;padding:20px 40px;border-bottom:1px solid #e1e4ee}} h1{{margin:0;font-size:26px}}
header p{{margin:4px 0 0;color:#5b647a}} main{{padding:24px 40px;max-width:1200px}}
.gate{{display:inline-block;padding:8px 20px;border-radius:6px;font-size:22px;font-weight:700;margin:8px 0 20px}}
.gate.OK{{background:#d3f0c3;color:#0b4f1c}} .gate.ERROR{{background:#fbd4d0;color:#7a0b0b}} .gate.UNKNOWN,.gate.WARN{{background:#fdeebc;color:#6b4a00}}
.tiles{{display:flex;flex-wrap:wrap;gap:12px;margin-bottom:24px}}
.tile{{background:#fff;border:1px solid #e1e4ee;border-radius:8px;padding:12px 18px;min-width:130px}}
.lbl{{color:#5b647a;font-size:12px;text-transform:uppercase}} .val{{font-size:26px;font-weight:700}} .sub{{color:#5b647a;font-size:12px}}
h2{{margin:28px 0 8px}} table{{width:100%;border-collapse:collapse;background:#fff;border:1px solid #e1e4ee;border-radius:8px}}
th,td{{text-align:left;padding:8px 12px;border-bottom:1px solid #eef0f6;vertical-align:top}} th{{background:#fafbfd;font-size:12px;color:#5b647a;text-transform:uppercase}}
td:nth-child(3){{font-family:ui-monospace,Menlo,monospace;font-size:12px}}
.sev{{font-weight:700}} .BLOCKER,.CRITICAL{{color:#c0281c}} .MAJOR{{color:#c46a00}} .MINOR{{color:#7a6a00}} .INFO{{color:#5b647a}}
</style></head><body>
<header><h1>{e(key)}</h1><p>SonarQube Community (local) &middot; generated {datetime.now():%Y-%m-%d %H:%M} &middot; open issues only</p></header>
<main>
<div class="gate {e(status)}">Quality gate: {e(status)}</div>
<div class="tiles">
{tile("Lines of code", measures.get("ncloc", "n/a"))}
{tile("Open issues", len(issues), ", ".join(f"{k.lower()} {v}" for k, v in sorted(counts.items(), key=lambda kv: sev_order.get(kv[0], 9))))}
{tile("Bugs", measures.get("bugs", "0"), "reliability " + rate("reliability_rating"))}
{tile("Vulnerabilities", measures.get("vulnerabilities", "0"), "security " + rate("security_rating"))}
{tile("Code smells", measures.get("code_smells", "0"), "maintainability " + rate("sqale_rating"))}
{tile("Security hotspots", measures.get("security_hotspots", "0"))}
{tile("Coverage", pct("coverage"))}
{tile("Duplication", pct("duplicated_lines_density"))}
</div>
<h2>Quality gate conditions</h2><table><tr><th>Metric</th><th>Status</th><th>Actual</th><th>Required</th></tr>{cond_rows}</table>
<h2>Issues ({len(issues)})</h2><table><tr><th>Severity</th><th>Type</th><th>Location</th><th>Message</th><th>Rule</th></tr>{issue_rows}</table>
<h2>Security hotspots ({len(hotspots)})</h2><table><tr><th>Probability</th><th>Location</th><th>Message</th></tr>{hot_rows}</table>
</main></body></html>"""

with open(out, "w", encoding="utf-8") as f:
    f.write(page_html)
print(out)
