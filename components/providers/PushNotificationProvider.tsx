"use client"

import React, { useEffect } from "react"
import { Capacitor } from "@capacitor/core"
import { pushNotificationService } from "@/lib/notifications/push-service"

export function PushNotificationProvider({
  children,
}: {
  children: React.ReactNode
}) {
  useEffect(() => {
    if (Capacitor.isNativePlatform()) {
      pushNotificationService.initialize()

      // Update last_seen periodically when app is active
      const interval = setInterval(() => {
        pushNotificationService.updateLastSeen()
      }, 5 * 60 * 1000) // Every 5 minutes

      return () => clearInterval(interval)
    }
  }, [])

  return <>{children}</>
}
