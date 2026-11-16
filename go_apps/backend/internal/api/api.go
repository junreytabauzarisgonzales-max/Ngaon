package api

import (
	"goapp/backend/internal/service"
)

type API struct {
	svc *service.Service
}

func New(svc *service.Service) *API {
	return &API{svc: svc}
}
