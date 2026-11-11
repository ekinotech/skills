import json, sys

kind, path = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(path))
except Exception:
    print("unavailable")
    sys.exit(0)

if kind == "gate":
    print(d["projectStatus"]["status"])
else:
    for f in d.get("facets", []):
        print(f["property"] + ": " + ", ".join(f"{v['val']}={v['count']}" for v in f["values"] if v["count"]))
    print("total:", d.get("total", 0))
    order = {"BLOCKER": 0, "CRITICAL": 1, "MAJOR": 2, "MINOR": 3, "INFO": 4}
    for i in sorted(d.get("issues", []), key=lambda i: order.get(i["severity"], 9))[:50]:
        comp = i["component"].split(":", 1)[-1]
        print(f"{i['severity']:8} {comp}:{i.get('line', '-')}  {i['message']}  [{i['rule']}]")
