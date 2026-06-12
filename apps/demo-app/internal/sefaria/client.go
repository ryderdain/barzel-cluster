// Package sefaria provides a thin client for the Sefaria HTTP API's search
// endpoint. It is borrowed (trimmed to the search path) from the chofesh CLI
// — github.com/ryderdain/chofesh, internal/sefaria — so the demo-app can drive
// real outbound API traffic and persist real results.
//
// Reference: https://developers.sefaria.org/reference/post-search-wrapper
package sefaria

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// DefaultBaseURL is the production Sefaria API host.
const DefaultBaseURL = "https://www.sefaria.org"

// DefaultUserAgent identifies this client to the Sefaria API.
const DefaultUserAgent = "brzl-demo-app/0.2 (+https://github.com/ryderdain/barzel-cluster)"

// Client is a Sefaria HTTP client. Use New.
type Client struct {
	baseURL    string
	httpClient *http.Client
	userAgent  string
}

// Option configures a Client.
type Option func(*Client)

// WithBaseURL overrides the default API base URL.
func WithBaseURL(u string) Option {
	return func(c *Client) {
		if u = strings.TrimRight(u, "/"); u != "" {
			c.baseURL = u
		}
	}
}

// WithHTTPClient overrides the underlying HTTP client — the demo-app injects one
// whose transport records every outbound call (for the api_calls log + metrics).
func WithHTTPClient(h *http.Client) Option {
	return func(c *Client) { c.httpClient = h }
}

// New constructs a Client with sensible defaults.
func New(opts ...Option) *Client {
	c := &Client{
		baseURL:    DefaultBaseURL,
		httpClient: &http.Client{Timeout: 30 * time.Second},
		userAgent:  DefaultUserAgent,
	}
	for _, opt := range opts {
		opt(c)
	}
	return c
}

// SearchField selects the analyzer field on the search index.
type SearchField string

const (
	// SearchFieldExact matches the literal text using the standard analyzer.
	SearchFieldExact SearchField = "exact"
	// SearchFieldNaiveLemmatizer matches with Sefaria's Hebrew-aware lemmatizer
	// — the most useful field for transliterated or unvocalized Hebrew queries.
	SearchFieldNaiveLemmatizer SearchField = "naive_lemmatizer"
)

// SearchRequest captures the subset of the search-wrapper body we expose.
type SearchRequest struct {
	Query string      `json:"query"`
	Type  string      `json:"type,omitempty"`
	Field SearchField `json:"field,omitempty"`
	Size  int         `json:"size,omitempty"`
}

// SearchResponse is the parsed response from search-wrapper.
type SearchResponse struct {
	Took int  `json:"took"`
	Hits Hits `json:"hits"`
}

// Hits is the outer hits container in an Elasticsearch response.
type Hits struct {
	Total    int
	MaxScore float64
	Hits     []Hit
}

// hitsRaw mirrors the wire shape; total may be int or {value, relation}.
type hitsRaw struct {
	Total    json.RawMessage `json:"total"`
	MaxScore float64         `json:"max_score"`
	Hits     []Hit           `json:"hits"`
}

// UnmarshalJSON handles the dual-shape `total` field (int or {value}).
func (h *Hits) UnmarshalJSON(data []byte) error {
	var raw hitsRaw
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	h.MaxScore = raw.MaxScore
	h.Hits = raw.Hits
	if len(raw.Total) == 0 {
		return nil
	}
	var n int
	if err := json.Unmarshal(raw.Total, &n); err == nil {
		h.Total = n
		return nil
	}
	var totalObj struct {
		Value int `json:"value"`
	}
	if err := json.Unmarshal(raw.Total, &totalObj); err == nil {
		h.Total = totalObj.Value
	}
	return nil
}

// Hit is a single Elasticsearch document hit.
type Hit struct {
	ID        string              `json:"_id"`
	Score     float64             `json:"_score"`
	Source    HitSource           `json:"_source"`
	Highlight map[string][]string `json:"highlight"`
}

// HitSource is the projected document body.
type HitSource struct {
	Ref             string   `json:"ref"`
	HeRef           string   `json:"heRef"`
	Version         string   `json:"version"`
	Lang            string   `json:"lang"`
	Categories      []string `json:"categories"`
	Exact           string   `json:"exact"`
	NaiveLemmatizer string   `json:"naive_lemmatizer"`
}

// Snippet returns a short, plain-text excerpt for a hit: the search highlight if
// present, otherwise the analyzer field text. Sefaria's <b>…</b> highlight tags
// are stripped so the result renders safely as escaped text (no markup, no XSS).
func (h Hit) Snippet() string {
	for _, key := range []string{"naive_lemmatizer", "exact"} {
		if frags := h.Highlight[key]; len(frags) > 0 {
			return truncate(stripTags(strings.Join(frags, " … ")), 400)
		}
	}
	if h.Source.NaiveLemmatizer != "" {
		return truncate(h.Source.NaiveLemmatizer, 400)
	}
	return truncate(h.Source.Exact, 400)
}

func stripTags(s string) string {
	r := strings.NewReplacer("<b>", "", "</b>", "", "<i>", "", "</i>", "")
	return r.Replace(s)
}

func truncate(s string, n int) string {
	s = strings.TrimSpace(s)
	if len(s) <= n {
		return s
	}
	return strings.TrimSpace(s[:n]) + "…"
}

// Search performs a search-wrapper POST against the Sefaria API.
func (c *Client) Search(ctx context.Context, req SearchRequest) (*SearchResponse, error) {
	if strings.TrimSpace(req.Query) == "" {
		return nil, fmt.Errorf("sefaria: search query must not be empty")
	}
	if req.Type == "" {
		req.Type = "text"
	}
	body, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("sefaria: marshal search request: %w", err)
	}
	endpoint := c.baseURL + "/api/search-wrapper"
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("sefaria: build search request: %w", err)
	}
	httpReq.Header.Set("Accept", "application/json")
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("User-Agent", c.userAgent)

	resp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("sefaria: search request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode/100 != 2 {
		snippet, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return nil, fmt.Errorf("sefaria: search returned HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(snippet)))
	}

	var out SearchResponse
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, fmt.Errorf("sefaria: decode search response: %w", err)
	}
	return &out, nil
}
