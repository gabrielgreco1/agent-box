import json, sys
for l in open(sys.argv[1]):
    try: o = json.loads(l)
    except Exception: continue
    t = o.get("type")
    if t == "system" and o.get("subtype") == "init":
        print("init: skills listing contains racky:", any("racky" in s for s in o.get("skills", [])), "| Skill tool present:", "Skill" in o.get("tools", []))
    if t == "assistant":
        for c in o["message"]["content"]:
            if c["type"] == "tool_use": print("tool_use", c["name"], json.dumps(c["input"])[:100])
            if c["type"] == "text": print("text", c["text"][:240])
    if t == "user":
        for c in o["message"]["content"]:
            if isinstance(c, dict) and c.get("type") == "tool_result": print("tool_result is_error=%s" % c.get("is_error"), str(c.get("content"))[:240])
    if t == "result": print("cost_usd", o.get("total_cost_usd"))
