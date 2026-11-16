package api

import (
	"fmt"
	"html/template"
	"net/http"
	"sort"
	"strings"
	"time"

	"goapp/backend/internal/service"
)

const pageCSS = `<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
:root{--g:#0B8A5B;--ink:#14201B;--muted:#66736D;--bg:#F4F6F5;--card:#fff;--line:#E2E7E4;--red:#D93A3A;--amber:#FFB020}
@media (prefers-color-scheme:dark){:root{--ink:#E8EEEB;--muted:#9AA8A1;--bg:#0F1714;--card:#1B2622;--line:#2A3732}}
*{box-sizing:border-box}body{margin:0;font:16px/1.45 system-ui,sans-serif;background:var(--bg);color:var(--ink);padding:16px}
.card{background:var(--card);border:1px solid var(--line);border-radius:18px;padding:18px;max-width:480px;margin:0 auto 14px}
h1{font-size:22px;margin:0 0 6px}.muted{color:var(--muted)}.amt{font-size:40px;font-weight:800;margin:8px 0}
button{width:100%;border:0;border-radius:14px;padding:16px;font-size:17px;font-weight:700;margin-top:10px;cursor:pointer}
.pay{background:var(--g);color:#fff}.fail{background:transparent;color:var(--red);border:1px solid var(--red)}
.tag{display:inline-block;padding:3px 10px;border-radius:20px;background:color-mix(in srgb,var(--g) 15%,transparent);color:var(--g);font-weight:700;font-size:13px}
table{width:100%;border-collapse:collapse}td{padding:8px 4px;border-top:1px solid var(--line);vertical-align:top}a{color:var(--g)}
.brand{font-weight:900;color:var(--g);font-size:20px}
</style>`

func peso(c int) string {
	neg := c < 0
	if neg {
		c = -c
	}
	s := fmt.Sprintf("%d", c/100)
	var b strings.Builder
	for i, ch := range s {
		if i > 0 && (len(s)-i)%3 == 0 {
			b.WriteByte(',')
		}
		b.WriteRune(ch)
	}
	out := fmt.Sprintf("₱%s.%02d", b.String(), c%100)
	if neg {
		return "-" + out
	}
	return out
}

var payTpl = template.Must(template.New("pay").Parse(`<!doctype html><html><head><title>Go Pay</title>` + pageCSS + `</head><body>
<div class="card"><div class="brand">Go · {{.Method}}</div><p class="muted">Development checkout (no real money moves).</p>
<div class="muted">{{.What}}</div><div class="amt">{{.Amount}}</div>
{{if .Done}}<p><span class="tag">{{.Done}}</span></p><p>You can go back to the app now.</p>
{{else}}<form method="post"><button class="pay" name="result" value="paid">Pay {{.Amount}}</button>
<button class="fail" name="result" value="failed">Simulate failed payment</button></form>{{end}}</div></body></html>`))

func (a *API) payPage(w http.ResponseWriter, r *http.Request) { a.renderPay(w, r, "") }

func (a *API) renderPay(w http.ResponseWriter, r *http.Request, done string) {
	kind, id := r.PathValue("kind"), r.PathValue("id")
	a.svc.Lock()
	defer a.svc.Unlock()
	data := map[string]string{"Done": done}
	switch kind {
	case "job":
		js := a.svc.St.Jobs[id]
		if js == nil {
			http.NotFound(w, r)
			return
		}
		data["Method"] = strings.ToUpper(js.Job.Payment.Method[:1]) + js.Job.Payment.Method[1:]
		data["What"] = "Booking " + js.Job.Code
		data["Amount"] = peso(js.Job.Fare.TotalCentavos)
		if done == "" && js.Job.Payment.Status == "paid" {
			data["Done"] = "Already paid"
		}
	case "topup":
		t := a.svc.St.Topups[id]
		if t == nil {
			http.NotFound(w, r)
			return
		}
		data["Method"] = strings.ToUpper(t.Method[:1]) + t.Method[1:]
		data["What"] = "Rider wallet top-up"
		data["Amount"] = peso(t.AmountCentavos)
		if done == "" && t.Status == "paid" {
			data["Done"] = "Already paid"
		}
	default:
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_ = payTpl.Execute(w, data)
}

func (a *API) payAction(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, 64<<10)
	_ = r.ParseForm()
	paid := r.FormValue("result") == "paid"
	kind, id := r.PathValue("kind"), r.PathValue("id")
	a.svc.Lock()
	result := "Payment failed"
	switch kind {
	case "job":
		if js := a.svc.St.Jobs[id]; js != nil && js.Job.Status == "pending_payment" && js.Job.Payment.Status != "paid" {
			if paid {
				js.Job.Payment.Status = "paid"
				result = "Payment successful"
				a.svc.AfterPayment(js)
			} else {
				js.Job.Payment.Status = "failed"
				a.svc.PublishJob(js)
			}
		}
	case "topup":
		if t := a.svc.St.Topups[id]; t != nil && t.Status != "paid" {
			if paid {
				t.Status = "paid"
				result = "Top-up successful"
				a.svc.AddTx(t.UserID, "topup", t.AmountCentavos, "", strings.ToUpper(t.Method[:1])+t.Method[1:]+" top-up")
				if rd := a.svc.St.Riders[t.UserID]; rd != nil {
					a.svc.Emit(t.UserID, "rider", "rider.profile_updated", map[string]any{"profile": rd.Profile})
				}
			} else {
				t.Status = "failed"
			}
		}
	}
	a.svc.Touch()
	a.svc.Unlock()
	a.renderPay(w, r, result)
}

var shareTpl = template.Must(template.New("share").Parse(`<!doctype html><html><head><title>Go trip {{.Code}}</title>
<meta http-equiv="refresh" content="10">` + pageCSS + `</head><body><div class="card"><div class="brand">Go</div>
<h1>{{.Code}} · {{.Status}}</h1><p class="muted">Live trip shared with you. This page refreshes every 10 seconds.</p>
<table><tr><td class="muted">From</td><td>{{.From}}</td></tr><tr><td class="muted">To</td><td>{{.To}}</td></tr>
{{if .Rider}}<tr><td class="muted">Rider</td><td>{{.Rider}}</td></tr>{{end}}</table>
{{if .Map}}<p><a href="{{.Map}}">Open rider location in Google Maps</a></p>{{end}}</div></body></html>`))

func (a *API) sharePage(w http.ResponseWriter, r *http.Request) {
	a.svc.Lock()
	defer a.svc.Unlock()
	js := a.svc.St.Jobs[a.svc.St.Shares[r.PathValue("token")]]
	if js == nil {
		http.NotFound(w, r)
		return
	}
	j := a.svc.JobView(js, "customer")
	d := map[string]any{"Code": j.Code, "Status": strings.ReplaceAll(j.Status, "_", " "), "From": j.Pickup.Address, "To": j.Dropoff.Address}
	if j.Rider != nil {
		d["Rider"] = fmt.Sprintf("%s · %s %s · %s", j.Rider.Name, j.Rider.Color, j.Rider.MakeModel, j.Rider.Plate)
		if j.Rider.Location != nil && service.IsLive(j.Status) {
			d["Map"] = fmt.Sprintf("https://www.google.com/maps?q=%f,%f", j.Rider.Location.Lat, j.Rider.Location.Lng)
		}
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_ = shareTpl.Execute(w, d)
}

var adminTpl = template.Must(template.New("admin").Parse(`<!doctype html><html><head><title>Go admin</title>` + pageCSS + `</head><body>
<div class="card"><div class="brand">Go admin</div><h1>Rider applications</h1>
{{if not .Riders}}<p class="muted">No riders yet.</p>{{end}}
<table>{{range .Riders}}<tr><td><b>{{.Name}}</b><br><span class="muted">{{.Phone}} · {{.Plate}}</span><br><span class="tag">{{.Status}}</span></td>
<td>{{if eq .Status "pending_review"}}<form method="post" action="/admin/riders/{{.UserID}}/approve?token={{$.Token}}"><button class="pay">Approve</button></form>
<form method="post" action="/admin/riders/{{.UserID}}/reject?token={{$.Token}}"><button class="fail">Reject</button></form>{{end}}
{{range .Docs}}<a href="{{.}}">doc</a> {{end}}</td></tr>{{end}}</table></div></body></html>`))

func extractAdminToken(r *http.Request) string {
	if t := r.URL.Query().Get("token"); t != "" {
		return t
	}
	if t := r.Header.Get("X-Admin-Token"); t != "" {
		return t
	}
	if strings.HasPrefix(r.Header.Get("Authorization"), "Bearer ") {
		return strings.TrimSpace(strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer "))
	}
	return ""
}

func (a *API) checkAdminAuth(w http.ResponseWriter, r *http.Request) (string, bool) {
	allowed, _, _ := a.svc.AllowRate("admin_ip", a.clientIP(r), a.svc.Cfg.AuthRateLimitPerMin, time.Minute)
	if !allowed {
		http.Error(w, "too many requests", http.StatusTooManyRequests)
		return "", false
	}
	tok := extractAdminToken(r)
	if !a.svc.VerifyAdminToken(tok) {
		http.Error(w, "admin token required: /admin?token=…", http.StatusUnauthorized)
		return "", false
	}
	return tok, true
}

func (a *API) adminPage(w http.ResponseWriter, r *http.Request) {
	tok, ok := a.checkAdminAuth(w, r)
	if !ok {
		return
	}
	a.svc.Lock()
	defer a.svc.Unlock()
	type row struct {
		UserID, Name, Phone, Plate, Status string
		Docs                               []string
	}
	var rows []row
	for uid, rd := range a.svc.St.Riders {
		u := a.svc.St.Users[uid]
		if u == nil {
			continue
		}
		plate := ""
		if rd.Profile.Vehicle != nil {
			plate = rd.Profile.Vehicle.Plate
		}
		var docs []string
		for _, k := range rd.Documents {
			if u := a.svc.FileURL(k); u != nil {
				docs = append(docs, *u)
			}
		}
		rows = append(rows, row{uid, u.Name, u.Phone, plate, rd.Profile.Status, docs})
	}
	sort.Slice(rows, func(i, j int) bool { return rows[i].Status > rows[j].Status })
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_ = adminTpl.Execute(w, map[string]any{"Riders": rows, "Token": tok})
}

func (a *API) adminRider(w http.ResponseWriter, r *http.Request) {
	tok, ok := a.checkAdminAuth(w, r)
	if !ok {
		return
	}
	a.svc.Lock()
	rd := a.svc.St.Riders[r.PathValue("id")]
	if rd != nil {
		approve := r.PathValue("action") == "approve"
		a.svc.SetRiderReview(rd, approve, "Documents unclear. Please upload sharper photos.")
	}
	a.svc.Unlock()
	http.Redirect(w, r, "/admin?token="+tok, http.StatusSeeOther)
}

func (a *API) indexPage(w http.ResponseWriter, _ *http.Request) {
	a.svc.Lock()
	users, jobs, live, online := len(a.svc.St.Users), len(a.svc.St.Jobs), 0, 0
	for _, js := range a.svc.St.Jobs {
		if service.IsLive(js.Job.Status) {
			live++
		}
	}
	for _, rd := range a.svc.St.Riders {
		if rd.Profile.IsOnline {
			online++
		}
	}
	a.svc.Unlock()
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	fmt.Fprintf(w, `<!doctype html><html><head><title>Go API</title>%s</head><body><div class="card"><div class="brand">Go API</div>
<h1>Running ✓</h1><table><tr><td class="muted">Users</td><td>%d</td></tr><tr><td class="muted">Jobs</td><td>%d (%d live)</td></tr>
<tr><td class="muted">Riders online</td><td>%d</td></tr><tr><td class="muted">WebSockets</td><td>%d</td></tr></table>
<p class="muted">API base: %s/api/v1</p></div></body></html>`, pageCSS, users, jobs, live, online, a.svc.Hub.Count(), a.svc.Cfg.PublicURL)
}
