package main

import (
	"html/template"
	"time"
)

// pageData is the view model rendered by homeTmpl.
type pageData struct {
	Query    string
	Size     int
	Exact    bool
	Took     int           // Sefaria 'took' ms for the current search
	HitCount int           // total hits reported for the current search
	Results  []resultView  // current search results
	Recent   []recentView  // recent searches from the DB
	Calls    []apiCallView // recent outbound API calls from the DB
	ErrMsg   string        // search/validation error, if any
}

type resultView struct {
	Rank    int
	Ref     string
	HeRef   string
	Snippet string
}

type recentView struct {
	Query     string
	Field     string
	HitCount  int
	CreatedAt time.Time
}

type apiCallView struct {
	Method     string
	URL        string
	Status     int
	DurationMS int
	CreatedAt  time.Time
}

// homeTmpl is the single server-rendered page: a search form, the current
// results, and two recent-activity panels fed from Postgres (so a fresh page
// load already shows persisted history — the point of the demo).
var homeTmpl = template.Must(template.New("home").Parse(`<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>brzl-demo · Sefaria search</title>
  <style>
    :root { color-scheme: light dark; }
    body { font-family: system-ui, sans-serif; max-width: 52rem; margin: 2rem auto; padding: 0 1rem; line-height: 1.5; }
    h1 { font-size: 1.4rem; } h2 { font-size: 1.05rem; margin-top: 2rem; border-bottom: 1px solid #8884; padding-bottom: .25rem; }
    form { display: flex; gap: .5rem; flex-wrap: wrap; align-items: center; margin: 1rem 0; }
    input[type=text] { flex: 1 1 16rem; padding: .5rem; font-size: 1rem; }
    input[type=number] { width: 4.5rem; padding: .5rem; }
    button { padding: .5rem 1rem; font-size: 1rem; cursor: pointer; }
    .hit { margin: .75rem 0; padding: .5rem .75rem; border-left: 3px solid #69c; background: #8881; }
    .hit .ref { font-weight: 600; } .hit .heref { opacity: .7; float: right; }
    .snippet { margin-top: .25rem; }
    .meta { opacity: .7; font-size: .9rem; }
    .err { color: #c33; font-weight: 600; }
    table { width: 100%; border-collapse: collapse; font-size: .9rem; }
    td, th { text-align: left; padding: .25rem .5rem; border-bottom: 1px solid #8883; vertical-align: top; }
    code { word-break: break-all; }
  </style>
</head>
<body>
  <h1>חופש · Sefaria search <span class="meta">(brzl-demo)</span></h1>
  <p class="meta">Searches the <a href="https://www.sefaria.org">Sefaria</a> library of Jewish texts.
     Each query and its results are written to CloudNativePG; every outbound API call is logged.</p>

  <form method="POST" action="/search">
    <input type="text" name="q" placeholder="e.g. shalom, moshe, tikkun olam" value="{{.Query}}" autofocus required>
    <label>size <input type="number" name="size" min="1" max="25" value="{{.Size}}"></label>
    <label><input type="checkbox" name="exact" {{if .Exact}}checked{{end}}> exact</label>
    <button type="submit">Search</button>
  </form>

  {{if .ErrMsg}}<p class="err">{{.ErrMsg}}</p>{{end}}

  {{if .Query}}
    <h2>Results for “{{.Query}}” <span class="meta">— {{.HitCount}} hits, {{.Took}} ms</span></h2>
    {{if .Results}}
      {{range .Results}}
        <div class="hit">
          <span class="heref">{{.HeRef}}</span>
          <span class="ref">{{.Rank}}. {{.Ref}}</span>
          <div class="snippet">{{.Snippet}}</div>
        </div>
      {{end}}
    {{else}}<p class="meta">No results.</p>{{end}}
  {{end}}

  <h2>Recent searches</h2>
  {{if .Recent}}
  <table>
    <tr><th>when</th><th>query</th><th>field</th><th>hits</th></tr>
    {{range .Recent}}<tr>
      <td class="meta">{{.CreatedAt.Format "15:04:05"}}</td>
      <td>{{.Query}}</td><td class="meta">{{.Field}}</td><td>{{.HitCount}}</td>
    </tr>{{end}}
  </table>
  {{else}}<p class="meta">None yet.</p>{{end}}

  <h2>Recent outbound API calls</h2>
  {{if .Calls}}
  <table>
    <tr><th>when</th><th>method</th><th>url</th><th>status</th><th>ms</th></tr>
    {{range .Calls}}<tr>
      <td class="meta">{{.CreatedAt.Format "15:04:05"}}</td>
      <td>{{.Method}}</td><td><code>{{.URL}}</code></td>
      <td>{{.Status}}</td><td>{{.DurationMS}}</td>
    </tr>{{end}}
  </table>
  {{else}}<p class="meta">None yet.</p>{{end}}
</body>
</html>`))
