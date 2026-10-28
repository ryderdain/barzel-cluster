# cold-records.jq — the cold log store's records, one plain JSON object for
# each record (docs/RECOVERY.md, "The cold records"). Read-only: jq reads the
# files and prints to stdout.
#
#   jq -c -f driver/lib/cold-records.jq [--arg from <UTC>] [--arg to <UTC>] <files>
#
# Each object: t (UTC, when the collector read the record), source, node,
# run and phase (run outputs), namespace (events, pod logs), body. The body
# is an object when the record's text is JSON (api-audit, openbao-audit,
# a pod that logs JSON), the event's object for k8s-event, else the text.
# The times from and to (ISO 8601 with Z) are optional.

# An OTLP AnyValue as plain JSON.
def plain:
  if type != "object" then .
  elif has("stringValue") then .stringValue
  elif has("intValue") then (.intValue | tonumber)
  elif has("doubleValue") then .doubleValue
  elif has("boolValue") then .boolValue
  elif has("arrayValue") then [.arrayValue.values[]? | plain]
  elif has("kvlistValue") then ([.kvlistValue.values[]? | {(.key): (.value | plain)}] | add // {})
  else . end;

# Text that is JSON becomes an object; other text stays as it is.
def body: plain | if type == "string" then (. as $text | try fromjson catch $text) else . end;

.resourceLogs[]
| (.resource.attributes | map({(.key): .value.stringValue}) | add) as $r
| .scopeLogs[].logRecords[]
| ((if (.timeUnixNano // "0") == "0" then .observedTimeUnixNano else .timeUnixNano end)
   | tonumber / 1e9 | floor | todate) as $t
| select(($ARGS.named.from == null or $t >= $ARGS.named.from)
         and ($ARGS.named.to == null or $t < $ARGS.named.to))
| {t: $t, source: $r["brzl.source"], node: $r["brzl.collector.node"],
   run: $r["brzl.run"], phase: $r["brzl.phase"],
   namespace: $r["k8s.namespace.name"], body: (.body | body)}
