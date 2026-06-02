// LuminaVaultClient/LuminaVaultClient/API/Billing/BillingUsageDTOs.swift
//
// MeUsageResponse and UsageDailyPointDTO were promoted to LuminaVaultShared
// in v0.59.0. The local definitions are now typealiases to avoid ambiguity.

import Foundation
import LuminaVaultShared

typealias UsageDailyPointDTO = LuminaVaultShared.UsageDailyPointDTO
typealias MeUsageResponse = LuminaVaultShared.MeUsageResponse
