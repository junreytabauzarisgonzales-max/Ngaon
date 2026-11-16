package app

import (
	"goapp/backend/internal/config"
	"goapp/backend/internal/integrations"
)

type MapsConfig = config.MapsConfig
type DiditConfig = config.DiditConfig
type PayMongoConfig = config.PayMongoConfig

type Maps = integrations.Maps
type Route = integrations.Route
type Didit = integrations.Didit
type PayMongo = integrations.PayMongo
type Checkout = integrations.Checkout
type CheckoutStatus = integrations.CheckoutStatus
type DiditSession = integrations.DiditSession

var NewMaps = integrations.NewMaps
var NewDidit = integrations.NewDidit
var NewPayMongo = integrations.NewPayMongo
var logIntegration = integrations.LogIntegration
