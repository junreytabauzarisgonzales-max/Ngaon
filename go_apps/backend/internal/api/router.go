package api

import (
	"context"
	"net/http"
	"time"
)

func (a *API) healthz(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	if a.svc.DB != nil {
		if err := a.svc.DB.PingContext(ctx); err != nil {
			http.Error(w, "db_unhealthy", http.StatusServiceUnavailable)
			return
		}
	}
	if a.svc.Redis != nil {
		if err := a.svc.Redis.Ping(ctx); err != nil {
			http.Error(w, "redis_unhealthy", http.StatusServiceUnavailable)
			return
		}
	}
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ok"))
}

// Routes wires every endpoint in API_CONTRACT.md plus dev pages.
func (a *API) Routes() http.Handler {
	mux := http.NewServeMux()
	p, authed := a.pub, a.authed
	v := "/api/v1"

	mux.HandleFunc("GET /healthz", a.healthz)
	mux.HandleFunc("GET /{$}", a.indexPage)

	// auth
	mux.HandleFunc("POST "+v+"/auth/otp/request", p(a.otpRequest))
	mux.HandleFunc("POST "+v+"/auth/otp/verify", p(a.otpVerify))
	mux.HandleFunc("POST "+v+"/auth/google", p(a.googleAuth))
	mux.HandleFunc("POST "+v+"/auth/facebook", p(a.facebookAuth))
	mux.HandleFunc("POST "+v+"/auth/refresh", p(a.refresh))
	mux.HandleFunc("POST "+v+"/auth/logout", p(a.logout))
	mux.HandleFunc("GET "+v+"/me", authed(a.getMe))
	mux.HandleFunc("PATCH "+v+"/me", authed(a.patchMe))
	mux.HandleFunc("DELETE "+v+"/me", authed(a.deleteMe))
	mux.HandleFunc("POST "+v+"/me/devices", authed(a.registerDevice))

	// places & geo
	mux.HandleFunc("GET "+v+"/me/places", authed(a.listPlaces))
	mux.HandleFunc("POST "+v+"/me/places", authed(a.addPlace))
	mux.HandleFunc("DELETE "+v+"/me/places/{id}", authed(a.deletePlace))
	mux.HandleFunc("GET "+v+"/geo/reverse", authed(a.geoReverse))
	mux.HandleFunc("GET "+v+"/geo/search", authed(a.geoSearch))
	mux.HandleFunc("GET "+v+"/service-area", authed(a.serviceArea))

	// merchants (public view)
	mux.HandleFunc("GET "+v+"/merchants", authed(a.listMerchants))
	mux.HandleFunc("GET "+v+"/merchants/{id}", authed(a.getMerchant))

	// quotes & jobs
	mux.HandleFunc("POST "+v+"/quotes", authed(a.createQuote))
	mux.HandleFunc("POST "+v+"/jobs", authed(a.createJob))
	mux.HandleFunc("GET "+v+"/jobs", authed(a.listJobs))
	mux.HandleFunc("GET "+v+"/jobs/{id}", authed(a.getJob))
	mux.HandleFunc("POST "+v+"/jobs/{id}/cancel", authed(a.cancelJob))
	mux.HandleFunc("POST "+v+"/jobs/{id}/confirm-items", authed(a.confirmItems))
	mux.HandleFunc("POST "+v+"/jobs/{id}/rate", authed(a.rateJob))
	mux.HandleFunc("POST "+v+"/jobs/{id}/share", authed(a.shareJob))
	mux.HandleFunc("POST "+v+"/jobs/{id}/sos", authed(a.sosJob))
	mux.HandleFunc("POST "+v+"/jobs/{id}/call", authed(a.callJob))
	mux.HandleFunc("GET "+v+"/jobs/{id}/messages", authed(a.listMessages))
	mux.HandleFunc("POST "+v+"/jobs/{id}/messages", authed(a.sendMessage))

	// uploads
	mux.HandleFunc("POST "+v+"/uploads", authed(a.createUpload))
	mux.HandleFunc("PUT /upload/{key...}", a.putUpload)
	mux.HandleFunc("GET /files/{key...}", a.getFile)

	// rider
	mux.HandleFunc("GET "+v+"/rider/me", authed(a.riderMe))
	mux.HandleFunc("PUT "+v+"/rider/me", authed(a.riderSubmit))
	mux.HandleFunc("POST "+v+"/rider/status", authed(a.riderStatus))
	mux.HandleFunc("POST "+v+"/rider/location", authed(a.riderLocationHTTP))
	mux.HandleFunc("GET "+v+"/rider/offers/current", authed(a.currentOffer))
	mux.HandleFunc("POST "+v+"/rider/offers/{id}/accept", authed(a.acceptOffer))
	mux.HandleFunc("POST "+v+"/rider/offers/{id}/decline", authed(a.declineOffer))
	mux.HandleFunc("GET "+v+"/rider/jobs/active", authed(a.riderActiveJob))
	mux.HandleFunc("GET "+v+"/rider/jobs", authed(a.riderJobs))
	mux.HandleFunc("POST "+v+"/rider/jobs/{id}/status", authed(a.riderJobStatus))
	mux.HandleFunc("GET "+v+"/rider/earnings", authed(a.riderEarnings))
	mux.HandleFunc("GET "+v+"/rider/wallet", authed(a.riderWallet))
	mux.HandleFunc("GET "+v+"/rider/wallet/transactions", authed(a.riderTransactions))
	mux.HandleFunc("POST "+v+"/rider/wallet/topups", authed(a.riderTopup))
	mux.HandleFunc("POST "+v+"/rider/kyc/session", authed(a.riderKycSession))

	// merchant
	mux.HandleFunc("GET "+v+"/merchant/me", authed(a.merchantMe))
	mux.HandleFunc("PATCH "+v+"/merchant/store", authed(a.patchStore))
	mux.HandleFunc("GET "+v+"/merchant/orders", authed(a.merchantOrders))
	mux.HandleFunc("GET "+v+"/merchant/orders/{id}", authed(a.merchantOrder))
	mux.HandleFunc("POST "+v+"/merchant/orders/{id}/accept", authed(a.merchantAccept))
	mux.HandleFunc("POST "+v+"/merchant/orders/{id}/reject", authed(a.merchantReject))
	mux.HandleFunc("POST "+v+"/merchant/orders/{id}/ready", authed(a.merchantReady))
	mux.HandleFunc("GET "+v+"/merchant/menu", authed(a.merchantMenu))
	mux.HandleFunc("POST "+v+"/merchant/menu/categories", authed(a.addCategory))
	mux.HandleFunc("PATCH "+v+"/merchant/menu/categories/{id}", authed(a.renameCategory))
	mux.HandleFunc("DELETE "+v+"/merchant/menu/categories/{id}", authed(a.deleteCategory))
	mux.HandleFunc("PUT "+v+"/merchant/menu/categories/order", authed(a.reorderCategories))
	mux.HandleFunc("POST "+v+"/merchant/menu/items", authed(a.createItem))
	mux.HandleFunc("PUT "+v+"/merchant/menu/items/{id}", authed(a.updateItem))
	mux.HandleFunc("DELETE "+v+"/merchant/menu/items/{id}", authed(a.deleteItem))
	mux.HandleFunc("PATCH "+v+"/merchant/menu/items/{id}/availability", authed(a.itemAvailability))
	mux.HandleFunc("PATCH "+v+"/merchant/menu/addon-options/{id}/availability", authed(a.optionAvailability))
	mux.HandleFunc("GET "+v+"/merchant/reports/sales", authed(a.salesReport))
	mux.HandleFunc("GET "+v+"/merchant/payouts", authed(a.listPayouts))

	// websocket
	mux.HandleFunc("GET /ws", a.ServeWS)

	// dev pages: payments, share links, admin
	mux.HandleFunc("GET /pay/{kind}/{id}", a.payPage)
	mux.HandleFunc("POST /pay/{kind}/{id}", a.payAction)
	mux.HandleFunc("GET /t/{token}", a.sharePage)
	mux.HandleFunc("POST /admin/riders/{id}/{action}", a.adminRider)
	mux.HandleFunc("GET /admin", a.adminPage)

	// provider webhooks + return pages (in-app browser lands here afterwards)
	mux.HandleFunc("POST /webhooks/paymongo", a.paymongoWebhook)
	mux.HandleFunc("POST /webhooks/didit", a.diditWebhook)
	mux.HandleFunc("GET /pay/return", a.returnPage("Payment received", "If you paid, your booking updates in a few seconds. You can close this page and go back to Ngaon."))
	mux.HandleFunc("GET /kyc/return", a.returnPage("Verification submitted", "Thanks! Close this page and go back to Ngaon Rider. Approval usually takes a few minutes."))

	return a.cors(securityHeaders(logging(mux)))
}
